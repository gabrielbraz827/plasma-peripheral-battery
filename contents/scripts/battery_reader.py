#!/usr/bin/env python3
"""
Battery reader for wireless peripherals (2.4 GHz USB dongles via hidraw, UPower, HeadsetControl).
Outputs JSON for the KDE Plasma 6 Peripheral Battery widget.
"""

import fcntl
import glob
import json
import os
import select
import shutil
import subprocess
import time


def _crc16_gtai(data: bytes) -> int:
    """CRC-16 used by the GTAI / Akko S9 Ultra protocol (init 0xFFFF, poly 0x8005 LSB-first)."""
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0x8005
            else:
                crc >>= 1
    return crc & 0xFFFF


def query_gtai_36eb_battery(hidraw_dev: str):
    """
    Query battery on GTAI / Akko S9 Ultra headsets (VID 0x36EB) via HID Report ID 0x02:
      TX (64 bytes): [0x02, 0x12, 0x01, 0x00, ..., crc_hi, crc_lo]
      RX (64 bytes): [0x02, 0x12, 0x01, status, battery_pct, ...]
        status == 0 -> success, battery_pct in 0..100
        status != 0 -> headset powered off / disconnected from dongle
    """
    fd = None
    try:
        fd = os.open(hidraw_dev, os.O_RDWR | os.O_NONBLOCK)

        # Drain any stale pending reports
        while select.select([fd], [], [], 0.01)[0]:
            try:
                os.read(fd, 64)
            except BlockingIOError:
                break

        cmd = bytearray(64)
        cmd[0] = 0x02
        cmd[1] = 0x12
        cmd[2] = 0x01
        cmd[3] = 0x00
        crc = _crc16_gtai(cmd[:62])
        cmd[62] = (crc >> 8) & 0xFF
        cmd[63] = crc & 0xFF

        for _ in range(5):
            os.write(fd, bytes(cmd))
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                resp = os.read(fd, 64)
                if len(resp) >= 5 and resp[0] == 0x02 and resp[1] == 0x12 and resp[2] == 0x01:
                    status = resp[3]
                    battery = int(resp[4])
                    if status == 0 and 0 < battery <= 100:
                        return {
                            "percentage": battery,
                            "charging": False,
                            "connected": True,
                            "note": "",
                        }
                    if status in (1, 2):
                        return {
                            "percentage": -1,
                            "charging": False,
                            "connected": False,
                            "note": "Headset powered off or out of range",
                        }
            time.sleep(0.08)

        return {
            "percentage": -1,
            "charging": False,
            "connected": False,
            "note": "No response from headset (powered off or asleep)",
        }
    except PermissionError:
        return {
            "percentage": -1,
            "charging": False,
            "connected": True,
            "note": f"Permission denied on {hidraw_dev} (udev rule required)",
        }
    except OSError as exc:
        return {
            "percentage": -1,
            "charging": False,
            "connected": False,
            "note": f"HID error: {exc}",
        }
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass


def _hidiocgfeature(length: int) -> int:
    return (3 << 30) | (ord("H") << 8) | 0x07 | (length << 16)


def _hidiocsfeature(length: int) -> int:
    return (3 << 30) | (ord("H") << 8) | 0x06 | (length << 16)


def parse_uevent(path: str) -> dict:
    info = {}
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    info[k] = v
    except OSError:
        pass
    return info


def query_rongyuan_3151_battery(hidraw_dev: str):
    """
    Query battery on Akko / RongYuan devices (VID 0x3151) using the 0xF7 status poll
    on the 64-byte Feature Report 0x00 (vendor usage page 0xFFFF).
    """
    fd = None
    try:
        fd = os.open(hidraw_dev, os.O_RDWR)
        cmd = bytearray(65)
        cmd[0] = 0x00  # Report ID 0
        cmd[1] = 0xF7  # Status/Battery poll
        cmd[8] = (0xFF - (sum(cmd[1:8]) & 0xFF)) & 0xFF
        fcntl.ioctl(fd, _hidiocsfeature(65), cmd)

        time.sleep(0.05)

        resp = bytearray(65)
        resp[0] = 0x00
        fcntl.ioctl(fd, _hidiocgfeature(65), resp)

        battery = int(resp[3])
        online = bool(resp[4])
        charging = bool(resp[5])

        if not online and battery == 0:
            return {
                "percentage": -1,
                "charging": False,
                "connected": False,
                "note": "Asleep / powered off",
            }

        if 0 <= battery <= 100:
            return {
                "percentage": battery,
                "charging": charging,
                "connected": True,
                "note": "",
            }
    except PermissionError:
        return {
            "percentage": -1,
            "charging": False,
            "connected": True,
            "note": f"Permission denied on {hidraw_dev} (udev rule required)",
        }
    except OSError as exc:
        return {
            "percentage": -1,
            "charging": False,
            "connected": False,
            "note": f"HID error: {exc}",
        }
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
    return None


def scan_hidraw_devices() -> list:
    devices = []
    seen_ids = set()

    for sys_path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        hidraw_name = os.path.basename(sys_path)
        dev_node = f"/dev/{hidraw_name}"
        uevent = parse_uevent(os.path.join(sys_path, "device", "uevent"))
        hid_id = uevent.get("HID_ID", "")
        hid_name = uevent.get("HID_NAME", "").strip()

        parts = hid_id.split(":")
        if len(parts) != 3:
            continue
        vid = parts[1][-4:].lower()
        pid = parts[2][-4:].lower()
        vid_pid = f"{vid}:{pid}"

        # 1) RongYuan / Akko 2.4 GHz mice & keyboards (VID 3151)
        if vid == "3151":
            rd_path = os.path.join(sys_path, "device", "report_descriptor")
            try:
                rd = open(rd_path, "rb").read()
            except OSError:
                rd = b""

            # Vendor-defined 0xFFFF 64-byte Feature Report: 06ffff0902...b102c0
            if rd.startswith(b"\x06\xff\xff\x09\x02") and vid_pid not in seen_ids:
                seen_ids.add(vid_pid)
                is_keyboard = "keyboard" in hid_name.lower()
                dev_type = "keyboard" if is_keyboard else "mouse"
                display_name = hid_name or ("2.4G Keyboard" if is_keyboard else "2.4G Mouse")
                res = query_rongyuan_3151_battery(dev_node)
                if res is not None:
                    devices.append({
                        "id": f"hidraw_{vid}_{pid}",
                        "name": display_name,
                        "type": dev_type,
                        "percentage": res["percentage"],
                        "charging": res["charging"],
                        "connected": res["connected"],
                        "supported": True,
                        "source": f"hidraw ({vid_pid})",
                        "note": res["note"],
                    })

        # 2) GTAI / Akko S9 Ultra / S9 Master headsets (VID 36eb)
        elif vid == "36eb" and vid_pid not in seen_ids:
            rd_path = os.path.join(sys_path, "device", "report_descriptor")
            try:
                rd = open(rd_path, "rb").read()
            except OSError:
                rd = b""

            # Interface with 63-byte Report ID 0x02 (Usage Page 0x8C)
            if b"\x85\x02" in rd:
                seen_ids.add(vid_pid)
                res = query_gtai_36eb_battery(dev_node)
                devices.append({
                    "id": f"hidraw_{vid}_{pid}",
                    "name": hid_name.replace("_Dongle", "").strip() or "Akko S9 Ultra",
                    "type": "headset",
                    "percentage": res["percentage"],
                    "charging": res["charging"],
                    "connected": res["connected"],
                    "supported": True,
                    "source": f"hidraw ({vid_pid})",
                    "note": res["note"],
                })

    return devices


def scan_upower_devices() -> list:
    devices = []
    if not shutil.which("upower"):
        return devices

    try:
        out = subprocess.check_output(["upower", "-e"], text=True, timeout=3)
    except (subprocess.SubprocessError, OSError):
        return devices

    ignored_types = {"line-power", "battery", "ups", "monitor", "display-device"}
    type_map = {
        "mouse": "mouse",
        "keyboard": "keyboard",
        "headset": "headset",
        "headphones": "headset",
        "audio-device": "headset",
        "gaming-input": "gamepad",
        "tablet": "tablet",
        "pen": "tablet",
    }

    for path in out.splitlines():
        path = path.strip()
        if not path or "DisplayDevice" in path or "line_power_" in path:
            continue
        if "/battery_BAT" in path:
            continue

        try:
            info = subprocess.check_output(["upower", "-i", path], text=True, timeout=3)
        except (subprocess.SubprocessError, OSError):
            continue

        dev_type_raw = ""
        model = ""
        percentage = -1
        charging = False

        for line in info.splitlines():
            s = line.strip()
            if s.startswith("model:"):
                model = s.split(":", 1)[1].strip()
            elif s.startswith("percentage:"):
                val = s.split(":", 1)[1].strip().rstrip("%")
                try:
                    percentage = int(round(float(val)))
                except ValueError:
                    pass
            elif s.startswith("state:"):
                state = s.split(":", 1)[1].strip().lower()
                charging = state in ("charging", "pending-charge")
            elif s in type_map or s in ignored_types:
                dev_type_raw = s

        if not dev_type_raw or dev_type_raw in ignored_types:
            continue
        if percentage < 0:
            continue

        devices.append({
            "id": f"upower_{os.path.basename(path)}",
            "name": model or dev_type_raw.capitalize(),
            "type": type_map.get(dev_type_raw, "other"),
            "percentage": percentage,
            "charging": charging,
            "connected": True,
            "supported": True,
            "source": "UPower",
            "note": "",
        })

    return devices


def scan_headsetcontrol() -> list:
    devices = []
    if not shutil.which("headsetcontrol"):
        return devices

    try:
        out = subprocess.check_output(
            ["headsetcontrol", "-o", "json"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        data = json.loads(out)
    except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
        return devices

    for dev in data.get("devices", []):
        batt = dev.get("battery", {})
        status = batt.get("status", "")
        level = batt.get("level", -1)
        if status == "BATTERY_UNAVAILABLE" and level < 0:
            continue
        devices.append({
            "id": f"hc_{dev.get('id_vendor', '0')}_{dev.get('id_product', '0')}",
            "name": dev.get("device", "Headset"),
            "type": "headset",
            "percentage": int(level) if isinstance(level, (int, float)) else -1,
            "charging": status == "BATTERY_CHARGING",
            "connected": True,
            "supported": True,
            "source": "HeadsetControl",
            "note": "",
        })

    return devices


def main():
    all_devices = []
    all_devices.extend(scan_hidraw_devices())
    all_devices.extend(scan_headsetcontrol())
    all_devices.extend(scan_upower_devices())

    print(json.dumps({"devices": all_devices}, ensure_ascii=False))


if __name__ == "__main__":
    main()

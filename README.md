# Plasma Peripheral Battery

A lightweight **KDE Plasma 6** panel widget (plasmoid) that displays battery levels of wireless peripherals (headsets, mice, keyboards, gamepads) connected via **2.4 GHz USB dongles (`hidraw`)**, **UPower / Bluetooth**, and **HeadsetControl**.

Built with zero external Python dependencies (Python 3 stdlib only).

## Features

- **Compact Panel View**: Shows peripheral icons and battery percentages directly in your KDE Plasma panel, with color-coded low-battery warnings.
- **Detailed Popup**: Click the widget to view progress bars, connection sources (`hidraw`, `UPower`, `HeadsetControl`), and manual refresh.
- **Middle-Click Refresh**: Middle-click the panel icon to force an immediate poll.
- **Configurable**: Adjust polling interval (5–300s), panel percentage visibility, and popup behavior via standard Plasma widget settings.

## Supported Devices & Protocols

| Source | Devices | Notes |
| --- | --- | --- |
| **GTAI / Akko `hidraw`** (`VID 0x36EB`) | **Akko S9 Ultra** (`36eb:1087`) and compatible GTAI 2.4 GHz headsets | Native 2.4 GHz dongle battery query via Report ID `0x02` (`02 12 01 00` + CRC-16 `0x8005`) |
| **RongYuan / Akko `hidraw`** (`VID 0x3151`) | Akko / MonsGeek / OEM 2.4 GHz wireless mice & keyboards (e.g. `3151:503d`, `3151:502d`) | Native 2.4 GHz dongle battery query via Feature Report `0xF7` |
| **UPower** | Bluetooth headsets, mice, keyboards, gamepads, and kernel-supported receivers (e.g. Logitech Bolt/Unifying) | Automatic detection (ignores laptop internal `BAT*` / AC adapters) |
| **HeadsetControl** *(optional)* | Any headset supported by [HeadsetControl](https://github.com/Sapd/HeadsetControl) | Automatically used if `headsetcontrol` is in `PATH` |

## Requirements

- **KDE Plasma 6.0+** (including `plasma5support` for the `executable` data source)
- **Python 3**
- `kpackagetool6` (included with KDE Plasma 6)

## Installation

```bash
git clone https://github.com/gabrielbraz827/plasma-peripheral-battery.git
cd plasma-peripheral-battery
./install.sh
```

Then add it to your panel:
1. Right-click your KDE Plasma panel → **Add or Manage Widgets...**
2. Search for **Peripheral Battery** and drag it onto your panel.

To reload Plasma after upgrading:
```bash
systemctl --user restart plasma-plasmashell.service
```

## udev Rules (Permissions for `hidraw`)

Some 2.4 GHz dongles require user read/write access to `/dev/hidraw*`. If a device reports a permission error, install the included udev rule:

```bash
sudo cp udev/99-peripheral-battery.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

*(You may need to unplug and replug your USB dongle once.)*

## Testing the Backend

You can test device detection directly from the terminal:

```bash
python3 contents/scripts/battery_reader.py
```

Example output:
```json
{
  "devices": [
    {
      "id": "hidraw_36eb_1087",
      "name": "GTAI Akko S9 Ultra",
      "type": "headset",
      "percentage": 99,
      "charging": false,
      "connected": true,
      "supported": true,
      "source": "hidraw (36eb:1087)",
      "note": ""
    },
    {
      "id": "hidraw_3151_503d",
      "name": "2.4G Wireless Mouse",
      "type": "mouse",
      "percentage": 100,
      "charging": false,
      "connected": true,
      "supported": true,
      "source": "hidraw (3151:503d)",
      "note": ""
    }
  ]
}
```

## Contributing

Have another 2.4 GHz dongle with a known HID battery protocol? Feel free to open an issue or pull request adding its reader function to `contents/scripts/battery_reader.py`!

## License

Licensed under the [Apache License 2.0](LICENSE).

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property var devices: []
    property bool loading: false
    property string lastError: ""

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int pollIntervalMs: Math.max(5, Plasmoid.configuration.pollInterval) * 1000
    readonly property bool showPercentageInPanel: Plasmoid.configuration.showPercentageInPanel
    readonly property bool showUnsupportedInPopup: Plasmoid.configuration.showUnsupportedInPopup

    // Resolve absolute path to the Python script inside the widget package
    readonly property string scriptPath: {
        var url = Qt.resolvedUrl("../scripts/battery_reader.py").toString()
        if (url.startsWith("file://")) {
            return decodeURIComponent(url.slice(7))
        }
        return url
    }

    // Devices with valid battery readings shown in the panel
    readonly property var panelDevices: {
        var list = []
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (d.supported && d.percentage >= 0) {
                list.push(d)
            }
        }
        return list
    }

    // Devices shown in the popup
    readonly property var popupDevices: {
        var list = []
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (d.supported || showUnsupportedInPopup) {
                list.push(d)
            }
        }
        return list
    }

    function iconForType(devType) {
        switch (devType) {
        case "mouse":
            return "input-mouse"
        case "headset":
            return "audio-headphones"
        case "keyboard":
            return "input-keyboard"
        case "gamepad":
            return "input-gamepad"
        default:
            return "battery-good"
        }
    }

    function colorForLevel(percentage, charging) {
        if (charging) {
            return Kirigami.Theme.positiveTextColor
        }
        if (percentage < 0) {
            return Kirigami.Theme.disabledTextColor
        }
        if (percentage <= 15) {
            return Kirigami.Theme.negativeTextColor
        }
        if (percentage <= 30) {
            return Kirigami.Theme.neutralTextColor
        }
        return Kirigami.Theme.textColor
    }

    function refreshBatteries() {
        if (loading) {
            return
        }
        loading = true
        var cmd = "python3 \"" + scriptPath + "\""
        executable.connectSource(cmd)
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            disconnectSource(sourceName)
            root.loading = false

            if (stdout.trim().length > 0) {
                try {
                    var parsed = JSON.parse(stdout)
                    root.devices = parsed.devices || []
                    root.lastError = ""
                } catch (e) {
                    root.lastError = "Failed to parse output: " + e
                }
            } else if (stderr.trim().length > 0) {
                root.lastError = stderr.trim()
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: true
        repeat: true
        onTriggered: root.refreshBatteries()
    }

    Component.onCompleted: {
        refreshBatteries()
    }

    toolTipMainText: "Peripheral Battery"
    toolTipSubText: {
        if (devices.length === 0) {
            return "No wireless peripherals detected"
        }
        var lines = []
        for (var i = 0; i < devices.length; i++) {
            var d = devices[i]
            if (d.supported && d.percentage >= 0) {
                lines.push(d.name + ": " + d.percentage + "%" + (d.charging ? " ⚡" : ""))
            } else if (d.note) {
                lines.push(d.name + ": " + d.note)
            }
        }
        return lines.join("\n")
    }

    // Compact representation in the panel
    compactRepresentation: MouseArea {
        id: compactRoot
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) {
                root.refreshBatteries()
            } else {
                root.expanded = !root.expanded
            }
        }

        Layout.minimumWidth: root.isVertical ? Kirigami.Units.iconSizes.small : compactFlow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: root.isVertical ? compactFlow.implicitHeight + Kirigami.Units.smallSpacing * 2 : Kirigami.Units.iconSizes.small
        Layout.preferredHeight: Layout.minimumHeight

        GridLayout {
            id: compactFlow
            anchors.centerIn: parent
            flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: Kirigami.Units.smallSpacing * 2
            rowSpacing: Kirigami.Units.smallSpacing

            // Fallback when no active device reports a battery percentage
            Kirigami.Icon {
                visible: root.panelDevices.length === 0
                source: "battery-missing"
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: Kirigami.Units.iconSizes.smallMedium
            }

            Repeater {
                model: root.panelDevices

                delegate: RowLayout {
                    spacing: Kirigami.Units.smallSpacing / 2

                    Kirigami.Icon {
                        source: root.iconForType(modelData.type)
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        color: root.colorForLevel(modelData.percentage, modelData.charging)
                        isMask: true
                    }

                    PlasmaComponents.Label {
                        visible: root.showPercentageInPanel
                        text: modelData.percentage + "%" + (modelData.charging ? "⚡" : "")
                        color: root.colorForLevel(modelData.percentage, modelData.charging)
                        font.pixelSize: Math.max(10, Kirigami.Theme.smallFont.pixelSize)
                        font.bold: modelData.percentage <= 20
                    }
                }
            }
        }
    }

    // Full representation (popup on click)
    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 10, contentCol.implicitHeight + Kirigami.Units.gridUnit * 4)

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: "Peripheral Battery"
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.loading
                    onClicked: root.refreshBatteries()
                    PlasmaComponents.ToolTip.text: "Refresh now"
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.mediumSpacing

            PlasmaExtras.PlaceholderMessage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.popupDevices.length === 0 && !root.lastError
                iconName: "battery-missing"
                text: "No peripherals detected"
                explanation: "Connect a wireless mouse, headset, or keyboard."
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: root.lastError.length > 0
                text: root.lastError
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.popupDevices

                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.mediumSpacing

                        Kirigami.Icon {
                            source: root.iconForType(modelData.type)
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents.Label {
                                    text: {
                                        if (modelData.supported && modelData.percentage >= 0) {
                                            return modelData.percentage + "%" + (modelData.charging ? " ⚡" : "")
                                        }
                                        return "N/A"
                                    }
                                    color: root.colorForLevel(modelData.percentage, modelData.charging)
                                    font.bold: true
                                }
                            }

                            PlasmaComponents.ProgressBar {
                                Layout.fillWidth: true
                                visible: modelData.supported && modelData.percentage >= 0
                                from: 0
                                to: 100
                                value: Math.max(0, modelData.percentage)
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: modelData.note ? (modelData.source + " • " + modelData.note) : modelData.source
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        visible: index < root.popupDevices.length - 1
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}

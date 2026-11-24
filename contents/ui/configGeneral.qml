import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_pollInterval: pollIntervalSpin.value
    property alias cfg_showPercentageInPanel: showPercentageCheck.checked
    property alias cfg_showUnsupportedInPopup: showUnsupportedCheck.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: pollIntervalSpin
            Kirigami.FormData.label: "Polling interval (seconds):"
            from: 5
            to: 300
            stepSize: 5
        }

        QQC2.CheckBox {
            id: showPercentageCheck
            Kirigami.FormData.label: "Panel:"
            text: "Show percentage next to icon in panel"
        }

        QQC2.CheckBox {
            id: showUnsupportedCheck
            Kirigami.FormData.label: "Popup:"
            text: "List connected dongles without battery reporting"
        }
    }
}

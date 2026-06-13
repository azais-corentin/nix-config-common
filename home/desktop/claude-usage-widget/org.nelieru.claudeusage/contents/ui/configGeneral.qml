import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_pollIntervalSeconds: pollSpin.value
    property alias cfg_command: commandField.text

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: "Refresh interval (seconds):"
            from: 15
            to: 3600
            stepSize: 5
        }

        QQC2.TextField {
            id: commandField
            Kirigami.FormData.label: "Usage command:"
            Layout.fillWidth: true
            placeholderText: "$HOME/.local/share/mise/shims/omp usage --json --provider anthropic"
        }
    }
}

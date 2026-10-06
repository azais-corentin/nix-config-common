import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_pollIntervalSeconds: pollSpin.value
    property alias cfg_panelWidth: widthSpin.value
    property alias cfg_estimator: estimatorField.text
    property alias cfg_server: serverField.text

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: widthSpin
            Kirigami.FormData.label: "Panel width (px):"
            from: 48
            to: 600
            stepSize: 8
        }

        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: "Refresh interval (seconds):"
            from: 15
            to: 3600
            stepSize: 5
        }

        QQC2.TextField {
            id: estimatorField
            Kirigami.FormData.label: "Estimator:"
            Layout.fillWidth: true
            placeholderText: "claude-usage-estimator"
        }

        QQC2.TextField {
            id: serverField
            Kirigami.FormData.label: "Server URL:"
            Layout.fillWidth: true
            placeholderText: "$CLAUDE_USAGE_SERVER, else http://vega:7781"
        }
    }
}

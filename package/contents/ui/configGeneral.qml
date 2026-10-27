import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_refreshInterval: interval.value
    property alias cfg_showWeeklyRing: weeklyRing.checked
    property alias cfg_credentialsPath: credentials.text
    property string cfg_centerValue

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: interval
            Kirigami.FormData.label: i18n("Update every (seconds):")
            from: 15
            to: 3600
            stepSize: 15
        }

        QQC2.ComboBox {
            id: center
            Kirigami.FormData.label: i18n("Number in tray icon:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Current session (5h)"), value: "session" },
                { text: i18n("Current week"), value: "weekly" },
                { text: i18n("Highest of all limits"), value: "max" }
            ]
            onActivated: cfg_centerValue = currentValue
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_centerValue))
        }

        QQC2.CheckBox {
            id: weeklyRing
            text: i18n("Show weekly usage as inner ring")
        }

        QQC2.TextField {
            id: credentials
            Kirigami.FormData.label: i18n("Credentials file:")
            placeholderText: "~/.claude/.credentials.json"
        }
    }
}

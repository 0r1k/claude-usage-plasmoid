import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    spacing: Kirigami.Units.largeSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: root.result && root.result.plan
                ? i18n("%1 plan", root.result.plan.charAt(0).toUpperCase() + root.result.plan.slice(1))
                : ""
            opacity: 0.7
        }
        PlasmaComponents3.BusyIndicator {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            visible: root.busy
            running: visible
        }
        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            enabled: !root.busy
            onClicked: root.refresh()
            PlasmaComponents3.ToolTip.text: i18n("Refresh now")
            PlasmaComponents3.ToolTip.visible: hovered
        }
        PlasmaComponents3.ToolButton {
            icon.name: "internet-web-browser"
            onClicked: Qt.openUrlExternally("https://claude.ai/settings/usage")
            PlasmaComponents3.ToolTip.text: i18n("Open claude.ai usage page")
            PlasmaComponents3.ToolTip.visible: hovered
        }
    }

    Repeater {
        model: root.usage ? root.usage.limits : []

        delegate: ColumnLayout {
            id: limitRow
            required property var modelData
            readonly property real pct: root.effectivePercent(modelData)

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: limitRow.modelData.label
                    font.bold: true
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    text: i18n("%1% used", Math.round(limitRow.pct))
                    color: limitRow.pct >= 75 ? root.colorFor(limitRow.pct) : Kirigami.Theme.textColor
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.45)
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)

                Rectangle {
                    width: parent.width * limitRow.pct / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.colorFor(limitRow.pct)
                    opacity: root.stale ? 0.55 : 1
                }
            }

            PlasmaComponents3.Label {
                text: root.resetText(limitRow.modelData)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: {
            const rows = root.usage && root.usage.breakdown ? root.usage.breakdown.filter(r => r.percent > 0) : [];
            if (!rows.length)
                return "";
            return i18n("This week: %1", rows.map(r => r.name + " " + r.percent + "%").join(" · "));
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: !!(root.usage && root.usage.extra)
        font: Kirigami.Theme.smallFont
        text: {
            const e = root.usage && root.usage.extra;
            if (!e)
                return "";
            return i18n("Extra usage: %1 / %2 %3", e.used, e.limit === null ? "∞" : e.limit, e.currency);
        }
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        text: root.statusText()
        color: !root.result || root.result.ok ? Kirigami.Theme.textColor
             : root.result.error === "token_expired" ? Kirigami.Theme.neutralTextColor
             : Kirigami.Theme.negativeTextColor
        opacity: !root.result || root.result.ok ? 0.7 : 1
    }

    // Keeps rows packed at the top when the popup is taller than needed.
    Item {
        Layout.fillHeight: true
    }
}

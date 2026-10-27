import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Tray icon: outer ring = number shown in the middle (session by default),
// thin inner ring = weekly limit.
MouseArea {
    id: compact

    readonly property real size: Math.min(width, height)
    readonly property real outerW: Math.max(1.5, size * 0.09)
    readonly property real innerW: Math.max(1.2, size * 0.06)
    readonly property real rOuter: (size - outerW) / 2
    readonly property real rInner: rOuter - outerW / 2 - innerW / 2 - Math.max(1, size * 0.04)
    readonly property bool showInner: Plasmoid.configuration.showWeeklyRing && root.centerLimit !== root.weeklyLimit
    // Free space inside the innermost ring for the number.
    readonly property real hole: 2 * ((showInner ? rInner - innerW / 2 : rOuter - outerW / 2))

    readonly property real outerPct: root.effectivePercent(root.centerLimit)
    readonly property real innerPct: root.effectivePercent(root.weeklyLimit)
    readonly property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

    property bool wasExpanded: false

    Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : Kirigami.Units.iconSizes.small

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    onPressed: wasExpanded = root.expanded
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton)
            root.refresh();
        else
            root.expanded = !wasExpanded;
    }

    Item {
        width: compact.size
        height: compact.size
        anchors.centerIn: parent
        opacity: root.stale ? 0.55 : 1

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: compact.trackColor
                strokeWidth: compact.outerW
                fillColor: "transparent"
                PathAngleArc {
                    centerX: compact.size / 2
                    centerY: compact.size / 2
                    radiusX: compact.rOuter
                    radiusY: compact.rOuter
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: compact.outerPct > 0 ? root.colorFor(compact.outerPct) : "transparent"
                strokeWidth: compact.outerW
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: compact.size / 2
                    centerY: compact.size / 2
                    radiusX: compact.rOuter
                    radiusY: compact.rOuter
                    startAngle: -90
                    sweepAngle: 3.6 * compact.outerPct
                }
            }
        }

        Shape {
            anchors.fill: parent
            visible: compact.showInner
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: compact.trackColor
                strokeWidth: compact.innerW
                fillColor: "transparent"
                PathAngleArc {
                    centerX: compact.size / 2
                    centerY: compact.size / 2
                    radiusX: compact.rInner
                    radiusY: compact.rInner
                    startAngle: 0
                    sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: compact.innerPct > 0 ? root.colorFor(compact.innerPct) : "transparent"
                strokeWidth: compact.innerW
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: compact.size / 2
                    centerY: compact.size / 2
                    radiusX: compact.rInner
                    radiusY: compact.rInner
                    startAngle: -90
                    sweepAngle: 3.6 * compact.innerPct
                }
            }
        }

        Text {
            anchors.centerIn: parent
            width: compact.hole * 1.05
            height: compact.hole * 0.85
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            fontSizeMode: Text.Fit
            minimumPixelSize: 5
            font.pixelSize: Math.max(6, compact.size * 0.55)
            font.bold: true
            color: Kirigami.Theme.textColor
            text: root.centerLimit ? Math.round(compact.outerPct) : "?"
        }
    }
}

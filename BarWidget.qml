import QtQuick
import qs.Commons
import qs.Ui

// Bar widget for the public IPv4 address. It draws the plugin service's
// state (Service.qml) and forwards clicks to it:
//   left click   copy the address and confirm with a notification
//   right click  look the address up again now
// The tooltip comes from the last lookup, so hovering costs no request.
//
// Settings (shell.json entry): "interval" seconds between lookups, 15-3600,
// default 60. e.g. `omarchy bar set lws.external-ip interval 120 --json`
BarWidget {
  id: root

  property var service: null

  readonly property string ipState: service ? service.ipState : "pending"
  readonly property bool attention: ipState === "stale" || ipState === "offline"
  readonly property string icon: ipState === "offline"
    ? String.fromCodePoint(0xF0A8E)  // nf-md-web_off
    : String.fromCodePoint(0xF059F)  // nf-md-web
  readonly property string labelText: service ? service.label : ""
  readonly property int interval: Number(setting("interval", 60))

  function resolveService() {
    var shellApi = bar ? bar.shell : null
    var found = shellApi && typeof shellApi.serviceFor === "function"
      ? shellApi.serviceFor(moduleName || "lws.external-ip") : null
    if (found !== service) service = found
  }

  function pushSettings() {
    if (service && typeof service.configure === "function") service.configure(interval)
  }

  onBarChanged: resolveService()
  onServiceChanged: pushSettings()
  onIntervalChanged: pushSettings()

  // The service may finish loading after the first bar does; keep looking
  // until it is there, and again if it is ever replaced.
  Timer {
    interval: 400
    repeat: true
    running: !root.service
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    active: root.attention
    dimmed: root.ipState === "pending"
    // Same side margin as the icon slots around it (7.5 px each side of a
    // 12 px glyph in a 27 px slot) and the bar's command modules.
    horizontalMargin: 7.5
    fixedWidth: root.vertical ? -1 : content.width + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: root.service ? root.service.tooltip : ""

    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.RightButton) root.service.refresh(true)
      else if (b === Qt.LeftButton) root.service.copy()
    }

    Item {
      id: content

      readonly property color ink: button.active && button.useActiveColor ? button.activeColor : button.foreground

      x: (button.width - width) / 2
      y: (button.height - height) / 2
      width: Style.bar.iconCanvas + (label.visible ? Style.space(4) + label.implicitWidth : 0)
      height: Style.bar.iconCanvas
      scale: button.pressScale

      OpticalGlyph {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        text: root.icon
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        paintedSize: Style.bar.iconSize
        color: content.ink
      }

      // Vertical bars show the icon alone, as the built-in widgets do.
      Text {
        id: label
        visible: !root.vertical && text !== ""
        x: Style.bar.iconCanvas + Style.space(4)
        // Center the figures rather than the line box, as BarIconButton does,
        // so the digits sit level with the icons beside them.
        y: (parent.height - height) / 2
          + (labelMetrics.descent - labelMetrics.ascent + labelMetrics.tightBoundingRect("0").height) / 2
        textFormat: Text.PlainText
        text: root.labelText
        color: content.ink
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: Style.duration(160) }
        }
      }

      FontMetrics {
        id: labelMetrics
        font: label.font
      }
    }
  }
}

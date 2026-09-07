import QtQuick
import QtQuick.Window

Window {
  id: overlay

  required property var bridge
  required property bool inputTransparent

  visible: true
  visibility: Window.FullScreen
  color: "transparent"
  flags: Qt.FramelessWindowHint
       | Qt.WindowStaysOnTopHint
       | Qt.Tool
       | (overlay.inputTransparent ? Qt.WindowTransparentForInput : 0)

  Rectangle {
    id: eventCard

    property real horizontalTarget: {
      if (overlay.bridge.direction === "left")
        return overlay.width * 0.12
      if (overlay.bridge.direction === "right")
        return overlay.width * 0.68
      return (overlay.width - width) / 2
    }

    x: horizontalTarget
    y: overlay.height * 0.17
    width: Math.min(520, overlay.width * 0.42)
    height: 148
    radius: 24
    visible: overlay.bridge.hasEvent
    color: "#D9181B22"
    border.width: 2
    border.color: overlay.bridge.accentColor
    opacity: 0.96

    Behavior on x {
      NumberAnimation {
        duration: 280
        easing.type: Easing.OutCubic
      }
    }

    Rectangle {
      id: pulse

      anchors.centerIn: icon
      width: 64
      height: 64
      radius: 32
      color: "transparent"
      border.color: overlay.bridge.accentColor
      border.width: 2
      opacity: 0

      SequentialAnimation {
        id: pulseAnimation

        NumberAnimation {
          target: pulse
          property: "scale"
          from: 0.7
          to: 1.7
          duration: 520
        }
        NumberAnimation {
          target: pulse
          property: "opacity"
          from: 0.65
          to: 0
          duration: 300
        }
      }
    }

    Text {
      id: icon

      anchors.right: parent.right
      anchors.rightMargin: 28
      anchors.verticalCenter: parent.verticalCenter
      text: overlay.bridge.icon
      font.pixelSize: 54
    }

    Column {
      anchors.right: icon.left
      anchors.rightMargin: 22
      anchors.left: parent.left
      anchors.leftMargin: 28
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10

      Text {
        width: parent.width
        text: overlay.bridge.title
        color: "#FFFFFF"
        font.family: "Noto Sans Arabic"
        font.pixelSize: 29
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
      }

      Text {
        width: parent.width
        text: overlay.bridge.directionLabel
        color: overlay.bridge.accentColor
        font.family: "Noto Sans Arabic"
        font.pixelSize: 18
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
      }
    }

    Connections {
      target: overlay.bridge

      function onEventChanged() {
        pulse.scale = 0.7
        pulse.opacity = 0.65
        pulseAnimation.restart()
      }
    }
  }
}

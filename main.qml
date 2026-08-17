import QtQuick

Item {
  id: root
  property QtObject bar: null
  property string moduleName: "io.github.brm-src.omatchday"
  property var settings: ({})
  implicitWidth: 32
  implicitHeight: 32
  Rectangle {
    anchors.fill: parent
    radius: 6
    color: "#e0228f"
    Text { anchors.centerIn: parent; text: "⚽"; color: "#111318" }
    MouseArea { anchors.fill: parent }
  }
}

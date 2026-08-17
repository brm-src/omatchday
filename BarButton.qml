import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.brm-src.omatchday"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⚽"
    tooltipText: "Omatchday · partidos"
  }
}

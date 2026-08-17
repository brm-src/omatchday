import QtQuick
import qs.Commons
import qs.Ui

BarIconButton {
  id: root
  property string moduleName: "io.github.brm-src.omatchday"
  property var settings: ({})
  slotSize: Style.bar.statusSlot
  opticalSize: 16
  text: "⚽"
  tooltipText: "Omatchday · partidos"
}

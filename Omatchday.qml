import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string pluginId: "io.github.brm-src.omatchday"
  readonly property string helperPath: Qt.resolvedUrl("omatchday.py").toString().replace("file://", "")
  readonly property string setupPath: Qt.resolvedUrl("configure-omatchday.sh").toString().replace("file://", "")
  readonly property var activeWindow: ToplevelManager.activeToplevel
  readonly property bool desktopVisible: !activeWindow
  readonly property var monthNames: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
  readonly property var weekdayNames: ["L", "M", "X", "J", "V", "S", "D"]
  readonly property var calendarCells: buildMonthCells(shownMonth)
  readonly property var upcomingEvents: events.filter(function(event) { return !root.isPast(event) })
  readonly property var previousEvents: events.filter(function(event) { return root.isPast(event) }).reverse()
  readonly property var selectedEvents: selectedDate === ""
    ? events
    : events.filter(function(event) { return String(event.date || "") === selectedDate })
  readonly property var nextEvent: upcomingEvents.length > 0 ? upcomingEvents[0] : null

  property var events: []
  property var teams: []
  property var leagues: []
  property string errorMessage: ""
  property string updatedAt: ""
  property bool expanded: false
  property bool showCalendar: false
  property string selectedDate: ""
  property date shownMonth: new Date()

  function pad2(value) { return value < 10 ? "0" + value : String(value) }

  function dateKey(value) {
    return value.getFullYear() + "-" + pad2(value.getMonth() + 1) + "-" + pad2(value.getDate())
  }

  function buildMonthCells(month) {
    var first = new Date(month.getFullYear(), month.getMonth(), 1)
    var mondayOffset = (first.getDay() + 6) % 7
    var cells = []
    for (var index = 0; index < 42; index++) {
      var value = new Date(month.getFullYear(), month.getMonth(), 1 + index - mondayOffset)
      cells.push({ date: dateKey(value), day: value.getDate(), inMonth: value.getMonth() === month.getMonth() })
    }
    return cells
  }

  function isPast(event) {
    return Boolean(event.completed) || String(event.state || "") === "post" || new Date(String(event.timestamp || "")) < new Date()
  }

  function eventOnDate(date) {
    for (var index = 0; index < events.length; index++) {
      if (String(events[index].date || "") === date) return true
    }
    return false
  }

  function isToday(date) { return date === dateKey(new Date()) }

  function monthLabel() { return monthNames[shownMonth.getMonth()] + " " + shownMonth.getFullYear() }

  function moveMonth(delta) {
    shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + delta, 1)
  }

  function teamAccent(team) {
    var value = String(team && team.color || "").replace("#", "")
    return value.length === 6 ? "#" + value : Color.accent
  }

  function initials(team) {
    var value = String(team && (team.abbreviation || team.shortName || team.name) || "?")
    return value.substring(0, 3).toUpperCase()
  }

  function eventLabel(event) {
    if (!event) return "Sin partidos"
    return String(event.home.shortName || event.home.name) + " — " + String(event.away.shortName || event.away.name)
  }

  function scoreLabel(event) {
    if (!event) return ""
    return String(event.home.score || "—") + "   " + String(event.away.score || "—")
  }

  function refresh() {
    if (!footballProc.running) footballProc.running = true
  }

  function applyPayload(raw) {
    try {
      var payload = JSON.parse(String(raw || "{}"))
      events = payload.events || []
      teams = payload.teams || []
      leagues = payload.leagues || []
      errorMessage = payload.error || ""
      updatedAt = payload.updated || ""
    } catch (error) {
      events = []
      errorMessage = "Omatchday no pudo leer la respuesta de fútbol."
    }
  }

  function toggle() { expanded = !expanded }

  function openSetup() {
    Quickshell.execDetached(["foot", "-e", "bash", root.setupPath])
  }

  function openEvent(event) {
    if (event && event.url) Quickshell.execDetached(["xdg-open", String(event.url)])
  }

  function selectDay(date) {
    if (!eventOnDate(date)) return
    selectedDate = selectedDate === date ? "" : date
  }

  function setupHint() {
    return "Configura equipos con: " + root.setupPath
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 900000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Process {
    id: footballProc
    command: ["python3", root.helperPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPayload(text)
    }
  }

  IpcHandler {
    target: root.pluginId
    function open(): string { root.expanded = true; return "ok" }
    function close(): string { root.expanded = false; return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.desktopVisible && (root.events.length > 0 || root.errorMessage !== "" || root.teams.length === 0)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: root.pluginId
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {
        x: card.x
        y: card.y
        width: card.visible ? card.width : 0
        height: card.visible ? card.height : 0
      }

      BorderSurface {
        id: card
        width: root.expanded ? 500 : 394
        height: Math.min(root.expanded ? content.implicitHeight + Style.space(34) : content.implicitHeight + Style.space(28), root.expanded ? parent.height - Style.bar.sizeHorizontal - Style.space(32) : 430)
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.bar.sizeHorizontal + Style.space(12)
        anchors.rightMargin: Style.gapsOut
        radius: Style.cornerRadius + 3
        color: Color.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.accent, 1)
        visible: root.desktopVisible
        clip: true

        Flickable {
          id: scroll
          anchors.fill: parent
          anchors.margins: Style.spacing.md
          contentWidth: width
          contentHeight: content.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: content
            width: scroll.width
            spacing: Style.spacing.sm

            Row {
              width: parent.width
              height: Style.space(26)
              spacing: Style.spacing.sm

              Column {
                width: parent.width - actions.width - Style.spacing.sm
                spacing: 1
                Text {
                  text: "OMATCHDAY"
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.5
                }
                Text {
                  text: root.teams.length > 0 ? root.teams.map(function(team) { return team.abbreviation || team.shortName }).join(" · ") : "CENTRO DE PARTIDOS"
                  color: Util.alpha(Color.foreground, 0.60)
                  font.family: Style.font.family
                  font.pixelSize: 9
                  elide: Text.ElideRight
                }
              }

              Row {
                id: actions
                spacing: Style.spacing.xs
                PanelActionButton {
                  size: Style.space(24)
                  iconText: root.expanded ? "−" : "+"
                  foreground: Color.foreground
                  hoverColor: Color.accent
                  onClicked: root.toggle()
                }
                PanelActionButton {
                  size: Style.space(24)
                  iconText: "↻"
                  foreground: Color.foreground
                  hoverColor: Color.accent
                  onClicked: root.refresh()
                }
              }
            }

            Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.accent, 0.42) }

            Rectangle {
              visible: root.teams.length === 0
              width: parent.width
              height: emptyColumn.implicitHeight + Style.spacing.md * 2
              radius: Style.cornerRadius
              color: Util.alpha(Color.accent, 0.11)
              border.width: 1
              border.color: Util.alpha(Color.accent, 0.38)
              Column {
                id: emptyColumn
                anchors.fill: parent
                anchors.margins: Style.spacing.md
                spacing: Style.spacing.xs
                Text { text: "ELIGE TUS EQUIPOS"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 0.8 }
                Text { width: parent.width; text: "Omatchday está listo. Solo falta configurar tus equipos para cargar partidos reales."; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; wrapMode: Text.Wrap }
                Text { width: parent.width; text: root.setupHint(); color: Util.alpha(Color.foreground, 0.62); font.family: Style.font.family; font.pixelSize: 10; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                Rectangle {
                  width: setupText.implicitWidth + 22
                  height: 30
                  radius: 7
                  color: setupMouse.containsMouse ? Util.alpha(Color.accent, 0.82) : Color.accent
                  Text { id: setupText; anchors.centerIn: parent; text: "Configurar ahora"; color: Color.background; font.family: Style.font.family; font.pixelSize: 11; font.bold: true }
                  MouseArea { id: setupMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSetup() }
                }
              }
            }

            Rectangle {
              visible: root.nextEvent !== null
              width: parent.width
              height: heroColumn.implicitHeight + Style.spacing.md * 2
              radius: Style.cornerRadius + 2
              color: Util.alpha(Color.foreground, 0.075)
              border.width: 1
              border.color: Util.alpha(root.nextEvent ? root.teamAccent(root.nextEvent.home) : Color.accent, 0.48)
              Column {
                id: heroColumn
                anchors.fill: parent
                anchors.margins: Style.spacing.md
                spacing: Style.spacing.xs
                Row {
                  width: parent.width
                  Text { width: parent.width - statusText.implicitWidth; text: root.nextEvent ? (root.nextEvent.day + "  ·  " + root.nextEvent.time) : ""; color: Color.accent; font.family: Style.font.family; font.pixelSize: 11; font.bold: true }
                  Text { id: statusText; text: root.nextEvent ? (root.nextEvent.state === "in" ? "EN VIVO" : "PRÓXIMO") : ""; color: root.nextEvent && root.nextEvent.state === "in" ? Color.accent : Util.alpha(Color.foreground, 0.58); font.family: Style.font.family; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
                }
                Row {
                  width: parent.width
                  height: 67
                  spacing: Style.spacing.sm
                  TeamBadge { team: root.nextEvent ? root.nextEvent.home : ({}) }
                  Column {
                    width: parent.width - 136
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { width: parent.width; text: root.nextEvent ? root.nextEvent.home.shortName : ""; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                    Text { width: parent.width; text: root.nextEvent ? root.scoreLabel(root.nextEvent) : ""; color: Color.accent; font.family: Style.font.family; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignRight }
                    Text { width: parent.width; text: root.nextEvent ? root.nextEvent.away.shortName : ""; color: Color.foreground; font.family: Style.font.family; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                  }
                  TeamBadge { team: root.nextEvent ? root.nextEvent.away : ({}) }
                }
                Text { width: parent.width; text: root.nextEvent ? (root.nextEvent.league + (root.nextEvent.venue ? "  ·  " + root.nextEvent.venue : "")) : ""; color: Util.alpha(Color.foreground, 0.56); font.family: Style.font.family; font.pixelSize: 10; elide: Text.ElideRight }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openEvent(root.nextEvent) }
            }

            Text { visible: root.upcomingEvents.length > 1; text: "PRÓXIMOS"; color: Util.alpha(Color.foreground, 0.58); font.family: Style.font.family; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }

            Repeater {
              model: Math.min(root.upcomingEvents.length > 0 ? root.upcomingEvents.length - 1 : 0, root.expanded ? 5 : 3)
              delegate: MatchRow { event: root.upcomingEvents[index + 1]; upcoming: true }
            }

            Text { visible: root.previousEvents.length > 0; text: "RESULTADOS"; color: Util.alpha(Color.foreground, 0.58); font.family: Style.font.family; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.0 }

            Repeater {
              model: Math.min(root.previousEvents.length, root.expanded ? 5 : 3)
              delegate: MatchRow { event: root.previousEvents[index]; upcoming: false }
            }

            Column {
              visible: root.expanded
              width: parent.width
              spacing: Style.spacing.xs
              Row {
                width: parent.width
                height: Style.space(25)
                PanelActionButton { size: Style.space(23); iconText: "‹"; foreground: Color.foreground; hoverColor: Color.accent; onClicked: root.moveMonth(-1) }
                Text { width: parent.width - 46; text: root.monthLabel(); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                PanelActionButton { size: Style.space(23); iconText: "›"; foreground: Color.foreground; hoverColor: Color.accent; onClicked: root.moveMonth(1) }
              }
              Grid {
                id: weekdays
                width: parent.width
                columns: 7
                columnSpacing: Style.spacing.xs
                Repeater {
                  model: root.weekdayNames
                  Text { required property string modelData; width: (weekdays.width - Style.spacing.xs * 6) / 7; height: 15; text: modelData; color: Util.alpha(Color.foreground, 0.45); font.family: Style.font.family; font.pixelSize: 9; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                }
              }
              Grid {
                id: calendar
                width: parent.width
                columns: 7
                columnSpacing: Style.spacing.xs
                rowSpacing: Style.spacing.xs
                Repeater {
                  model: root.calendarCells
                  Rectangle {
                    required property var modelData
                    width: (calendar.width - Style.spacing.xs * 6) / 7
                    height: Style.space(23)
                    radius: Style.cornerRadius
                    color: root.selectedDate === modelData.date ? Util.alpha(Color.accent, 0.38) : (root.isToday(modelData.date) ? Color.accent : (root.eventOnDate(modelData.date) ? Util.alpha(Color.accent, 0.16) : "transparent"))
                    border.width: root.eventOnDate(modelData.date) && !root.isToday(modelData.date) ? 1 : 0
                    border.color: Util.alpha(Color.accent, 0.62)
                    Text { anchors.centerIn: parent; text: modelData.day; color: root.isToday(modelData.date) || root.selectedDate === modelData.date ? Color.background : (modelData.inMonth ? Color.foreground : Util.alpha(Color.foreground, 0.24)); font.family: Style.font.family; font.pixelSize: 10; font.bold: root.eventOnDate(modelData.date) || root.isToday(modelData.date) }
                    MouseArea { anchors.fill: parent; enabled: root.eventOnDate(modelData.date); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectDay(modelData.date) }
                  }
                }
              }
            }

            Text {
              visible: root.selectedDate !== ""
              width: parent.width
              text: root.selectedEvents.length > 0 ? "PARTIDOS DEL " + root.selectedDate : "SIN PARTIDOS"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: 10
              font.bold: true
              font.letterSpacing: 0.8
            }

            Text {
              visible: root.events.length === 0
              width: parent.width
              text: root.errorMessage || "No hay partidos en este rango."
              color: Util.alpha(Color.foreground, 0.65)
              font.family: Style.font.family
              font.pixelSize: 11
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
            }

            Row {
              width: parent.width
              spacing: Style.spacing.sm
              Text { width: parent.width - refreshLabel.implicitWidth; text: root.updatedAt ? "Fuente: ESPN · actualizado " + root.updatedAt.substring(11, 16) : "Fuente: ESPN"; color: Util.alpha(Color.foreground, 0.38); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
              Text { id: refreshLabel; text: "↻ " + (root.expanded ? "actualizar" : "" ); color: Color.accent; font.family: Style.font.family; font.pixelSize: 9; font.underline: refreshMouse.containsMouse; MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refresh() } }
            }
          }
        }
      }
    }
  }

  component TeamBadge: Rectangle {
    property var team: ({})
    width: 56
    height: 56
    radius: 12
    color: Util.alpha(root.teamAccent(team), 0.16)
    border.width: 1
    border.color: Util.alpha(root.teamAccent(team), 0.58)
    Image {
      anchors.fill: parent
      anchors.margins: 8
      source: String(team.logo || "")
      fillMode: Image.PreserveAspectFit
      smooth: true
      visible: status === Image.Ready
    }
    Text { anchors.centerIn: parent; text: root.initials(team); color: root.teamAccent(team); font.family: Style.font.family; font.pixelSize: 12; font.bold: true; visible: parent.children.length === 0 || !parent.children[0].visible }
  }

  component MatchRow: Rectangle {
    property var event: ({})
    property bool upcoming: true
    width: content.width
    height: 42
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, 0.055)
    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.sm
      anchors.rightMargin: Style.spacing.sm
      spacing: Style.spacing.sm
      Text { width: 55; anchors.verticalCenter: parent.verticalCenter; text: event.day; color: upcoming ? Color.accent : Util.alpha(Color.foreground, 0.50); font.family: Style.font.family; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight }
      Column {
        width: parent.width - 55 - 72 - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text { width: parent.width; text: root.eventLabel(event); color: Color.foreground; font.family: Style.font.family; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight }
        Text { width: parent.width; text: event.league || event.status || ""; color: Util.alpha(Color.foreground, 0.46); font.family: Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
      }
      Text { width: 72; anchors.verticalCenter: parent.verticalCenter; text: upcoming ? event.time : root.scoreLabel(event); color: upcoming ? Color.foreground : Color.accent; font.family: Style.font.family; font.pixelSize: upcoming ? 11 : 12; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
    }
    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openEvent(event) }
  }
}

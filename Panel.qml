import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.brm-src.omatchday"
  ipcTarget: "io.github.brm-src.omatchday"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string helperPath: Qt.resolvedUrl("omatchday.py").toString().replace("file://", "")
  readonly property string setupPath: Qt.resolvedUrl("configure-omatchday.sh").toString().replace("file://", "")
  readonly property string barLabel: teams.length > 0 ? "⚽ " + String(teams[0].abbreviation || teams[0].shortName || teams[0].name).substring(0, 8) : "⚽"
  readonly property var upcomingEvents: events.filter(function(event) { return !root.isPast(event) })
  readonly property var previousEvents: events.filter(function(event) { return root.isPast(event) }).reverse()
  readonly property var selectedEvents: selectedDate === "" ? events : events.filter(function(event) { return String(event.date || "") === selectedDate })
  readonly property var nextEvent: upcomingEvents.length > 0 ? upcomingEvents[0] : null
  readonly property var monthCells: buildMonthCells(shownMonth)

  property var events: []
  property var teams: []
  property var leagues: []
  property string errorMessage: ""
  property string updatedAt: ""
  property string selectedDate: ""
  property string view: "agenda"
  property date shownMonth: new Date()
  property date today: new Date()

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
    return Boolean(event.completed) || String(event.state || "") === "post" || new Date(String(event.timestamp || "")) < root.today
  }

  function eventOnDate(date) {
    for (var index = 0; index < events.length; index++) {
      if (String(events[index].date || "") === date) return true
    }
    return false
  }

  function isToday(date) { return date === dateKey(root.today) }

  function monthLabel() {
    var locale = Qt.locale("es_CL")
    return locale.monthName(shownMonth.getMonth(), Locale.LongFormat) + " " + shownMonth.getFullYear()
  }

  function moveMonth(delta) {
    shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + delta, 1)
  }

  function teamColor(team) {
    var value = String(team && team.color || "").replace("#", "")
    return value.length === 6 ? "#" + value : (bar ? bar.barForeground : Color.accent)
  }

  function initials(team) {
    return String(team && (team.abbreviation || team.shortName || team.name) || "?").substring(0, 3).toUpperCase()
  }

  function eventLabel(event) {
    if (!event) return "Sin partidos"
    return String(event.home.shortName || event.home.name) + " — " + String(event.away.shortName || event.away.name)
  }

  function scoreLabel(event) {
    if (!event) return ""
    return String(event.home.score || "—") + "   " + String(event.away.score || "—")
  }

  function statusLabel(event) {
    if (!event) return ""
    if (event.state === "in") return "EN VIVO"
    if (event.completed || event.state === "post") return "FINAL"
    return "PRÓXIMO"
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
      if (selectedDate !== "" && !eventOnDate(selectedDate)) selectedDate = ""
    } catch (error) {
      events = []
      errorMessage = "No se pudo leer la respuesta de fútbol."
    }
  }

  function openFromHotkey() {
    root.controller.show()
    root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function open() { openFromHotkey() }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }

  function openEvent(event) {
    if (event && event.url) Quickshell.execDetached(["xdg-open", String(event.url)])
  }

  function openSetup() {
    Quickshell.execDetached(["foot", "-e", "bash", root.setupPath])
  }

  function selectDay(date) {
    if (!eventOnDate(date)) return
    selectedDate = selectedDate === date ? "" : date
    view = "results"
  }

  Component.onCompleted: refresh()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.today = date
  }

  Timer {
    interval: Math.max(5, parseInt(root.setting("refreshMinutes", 15), 10) || 15) * 60000
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contentColumn
        width: scroll.width
        spacing: Style.space(11)

        Row {
          width: parent.width
          spacing: Style.space(8)
          Column {
            width: parent.width - panelActions.width - Style.space(8)
            spacing: 1
            Text { text: "OMATCHDAY"; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.5 }
            Text { text: root.teams.length > 0 ? root.teams.map(function(team) { return team.abbreviation || team.shortName }).join(" · ") : "CENTRO DE PARTIDOS"; color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.5); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 9; elide: Text.ElideRight }
          }
          Row {
            id: panelActions
            spacing: Style.space(3)
            Button { iconText: "↻"; foreground: root.bar ? root.bar.barForeground : Color.foreground; onClicked: root.refresh() }
            Button { iconText: "×"; foreground: root.bar ? root.bar.barForeground : Color.foreground; onClicked: root.close() }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.accent, 0.45) }

        Rectangle {
          visible: root.nextEvent !== null
          width: parent.width
          height: heroColumn.implicitHeight + Style.space(24)
          radius: Style.cornerRadius + 2
          color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.07)
          border.width: 1
          border.color: Util.alpha(root.nextEvent ? root.teamColor(root.nextEvent.home) : Color.accent, 0.55)
          Column {
            id: heroColumn
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(7)
            Row {
              width: parent.width
              Text { width: parent.width - heroStatus.implicitWidth; text: root.nextEvent ? root.nextEvent.day + "  ·  " + root.nextEvent.time : ""; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 11; font.bold: true }
              Text { id: heroStatus; text: root.statusLabel(root.nextEvent); color: root.nextEvent && root.nextEvent.state === "in" ? Color.accent : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.4); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.8 }
            }
            Row {
              width: parent.width
              height: 70
              spacing: Style.space(9)
              TeamBadge { team: root.nextEvent ? root.nextEvent.home : ({}) }
              Column {
                width: parent.width - 130
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { width: parent.width; text: root.nextEvent ? root.nextEvent.home.shortName : ""; color: root.bar ? root.bar.barForeground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                Text { width: parent.width; text: root.scoreLabel(root.nextEvent); color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 18; font.bold: true; horizontalAlignment: Text.AlignRight }
                Text { width: parent.width; text: root.nextEvent ? root.nextEvent.away.shortName : ""; color: root.bar ? root.bar.barForeground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
              }
              TeamBadge { team: root.nextEvent ? root.nextEvent.away : ({}) }
            }
            Text { width: parent.width; text: root.nextEvent ? root.nextEvent.league + (root.nextEvent.venue ? "  ·  " + root.nextEvent.venue : "") : ""; color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.5); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; elide: Text.ElideRight }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openEvent(root.nextEvent) }
        }

        Row {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: [["agenda", "PRÓXIMOS"], ["results", "RESULTADOS"], ["calendar", "CALENDARIO"]]
            delegate: Rectangle {
              required property var modelData
              width: (parent.width - 10) / 3
              height: 28
              radius: 7
              color: root.view === modelData[0] ? Util.alpha(Color.accent, 0.24) : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.06)
              Text { anchors.centerIn: parent; text: modelData[1]; color: root.view === modelData[0] ? Color.accent : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.35); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5 }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.view = modelData[0] }
            }
          }
        }

        Text { visible: root.view === "agenda" && root.upcomingEvents.length > 0; text: "PRÓXIMOS PARTIDOS"; color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.35); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.9 }
        Repeater { visible: root.view === "agenda"; model: Math.min(root.upcomingEvents.length, 6); delegate: MatchRow { event: root.upcomingEvents[index]; upcoming: true } }

        Text { visible: root.view === "results" && root.selectedDate === "" && root.previousEvents.length > 0; text: "ÚLTIMOS RESULTADOS"; color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.35); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.9 }
        Repeater { visible: root.view === "results" && root.selectedDate === ""; model: Math.min(root.previousEvents.length, 6); delegate: MatchRow { event: root.previousEvents[index]; upcoming: false } }
        Text { visible: root.view === "results" && root.selectedDate !== ""; text: "PARTIDOS DEL " + root.selectedDate; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.8 }
        Repeater { visible: root.view === "results" && root.selectedDate !== ""; model: root.selectedEvents.length; delegate: MatchRow { event: root.selectedEvents[index]; upcoming: !root.isPast(root.selectedEvents[index]) } }

        Column {
          visible: root.view === "calendar"
          width: parent.width
          spacing: Style.space(6)
          Row {
            width: parent.width
            height: 25
            Button { iconText: "‹"; foreground: root.bar ? root.bar.barForeground : Color.foreground; onClicked: root.moveMonth(-1) }
            Text { width: parent.width - 46; text: root.monthLabel(); color: root.bar ? root.bar.barForeground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            Button { iconText: "›"; foreground: root.bar ? root.bar.barForeground : Color.foreground; onClicked: root.moveMonth(1) }
          }
          Grid { id: weekdayGrid; width: parent.width; columns: 7; columnSpacing: Style.space(2); Repeater { model: ["L", "M", "X", "J", "V", "S", "D"]; Text { required property string modelData; width: (weekdayGrid.width - 12) / 7; height: 14; text: modelData; color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.8); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 9; font.bold: true; horizontalAlignment: Text.AlignHCenter } } }
          Grid { id: calendarGrid; width: parent.width; columns: 7; columnSpacing: Style.space(2); rowSpacing: Style.space(2); Repeater { model: root.monthCells; Rectangle { required property var modelData; width: (calendarGrid.width - 12) / 7; height: 24; radius: 6; color: root.isToday(modelData.date) ? Color.accent : (root.eventOnDate(modelData.date) ? Util.alpha(Color.accent, 0.16) : "transparent"); border.width: root.eventOnDate(modelData.date) && !root.isToday(modelData.date) ? 1 : 0; border.color: Util.alpha(Color.accent, 0.60); Text { anchors.centerIn: parent; text: modelData.day; color: root.isToday(modelData.date) ? Color.background : (modelData.inMonth ? (root.bar ? root.bar.barForeground : Color.foreground) : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.25)); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: root.eventOnDate(modelData.date) || root.isToday(modelData.date) } MouseArea { anchors.fill: parent; enabled: root.eventOnDate(modelData.date); cursorShape: Qt.PointingHandCursor; onClicked: root.selectDay(modelData.date) } } } }
        }

        Rectangle {
          visible: root.teams.length === 0
          width: parent.width
          height: setupColumn.implicitHeight + 22
          radius: 8
          color: Util.alpha(Color.accent, 0.11)
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.38)
          Column { id: setupColumn; anchors.fill: parent; anchors.margins: 11; spacing: 5; Text { text: "ELIGE TUS EQUIPOS"; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.8 } Text { width: parent.width; text: "Configura ligas y equipos desde el asistente."; color: root.bar ? root.bar.barForeground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 11; wrapMode: Text.Wrap } Rectangle { width: setupButtonText.implicitWidth + 20; height: 28; radius: 7; color: setupButtonMouse.containsMouse ? Util.alpha(Color.accent, 0.8) : Color.accent; Text { id: setupButtonText; anchors.centerIn: parent; text: "Configurar"; color: Color.background; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: true } MouseArea { id: setupButtonMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSetup() } } }
        }

        Text { visible: root.events.length === 0 && root.teams.length > 0; width: parent.width; text: root.errorMessage || "No hay partidos en el rango configurado."; color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.5); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 11; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Text { width: parent.width; text: root.updatedAt ? "ESPN · actualizado " + root.updatedAt.substring(11, 16) : "ESPN"; color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.42); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 9 }
      }
    }
  }

  component TeamBadge: Rectangle {
    property var team: ({})
    width: 54
    height: 54
    radius: 12
    color: Util.alpha(root.teamColor(team), 0.16)
    border.width: 1
    border.color: Util.alpha(root.teamColor(team), 0.62)
    Image { id: logo; anchors.fill: parent; anchors.margins: 8; source: String(team.logo || ""); fillMode: Image.PreserveAspectFit; asynchronous: true; smooth: true }
    Text { anchors.centerIn: parent; text: root.initials(team); color: root.teamColor(team); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 12; font.bold: true; visible: logo.status !== Image.Ready }
  }

  component MatchRow: Rectangle {
    property var event: ({})
    property bool upcoming: true
    width: contentColumn.width
    height: 43
    radius: 8
    color: rowMouse.containsMouse ? Util.alpha(Color.accent, 0.16) : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.055)
    Row {
      anchors.fill: parent
      anchors.leftMargin: 9
      anchors.rightMargin: 9
      spacing: 8
      Text { width: 56; anchors.verticalCenter: parent.verticalCenter; text: event.day; color: upcoming ? Color.accent : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.52); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 10; font.bold: true; elide: Text.ElideRight }
      Column { width: parent.width - 56 - 78 - parent.spacing * 2; anchors.verticalCenter: parent.verticalCenter; spacing: 1; Text { width: parent.width; text: root.eventLabel(event); color: root.bar ? root.bar.barForeground : Color.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight } Text { width: parent.width; text: event.league || event.status || ""; color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.45); font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: 9; elide: Text.ElideRight } }
      Text { width: 78; anchors.verticalCenter: parent.verticalCenter; text: upcoming ? event.time : root.scoreLabel(event); color: upcoming ? (root.bar ? root.bar.barForeground : Color.foreground) : Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: upcoming ? 11 : 12; font.bold: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
    }
    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openEvent(event) }
  }
}

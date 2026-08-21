import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Reminder setup and active-timer management inside Unified Launcher. Omarchy's
// reminder command and transient systemd timers remain the single backend.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string pluginDir: ""
  property bool active: false
  property string mode: "manage"
  property string filterText: ""
  property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property int cornerRadius: Style.cornerRadius
  property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  property string step: "minutes"
  property string minutes: ""
  property var reminders: []
  property int selectedIndex: 0
  property bool cursorActive: true
  property bool confirmOpen: false
  property bool confirmClear: false
  property string confirmUnit: ""
  property string confirmLabel: ""

  readonly property bool setting: mode === "set"
  readonly property int count: displayModel.count
  readonly property string promptText: setting
    ? (step === "message" ? "Reminder message (optional)…" : "Remind in minutes…")
    : "Search reminders…"
  readonly property int preferredHeight: setting
    ? 0
    : Math.max(Style.space(104), Math.min(Style.space(400), count * rowHeight))

  signal closeRequested()
  signal filterRequested(string value)

  function resetForOpen() {
    root.confirmOpen = false
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()

    if (root.setting) {
      root.step = "minutes"
      root.minutes = ""
    } else {
      root.refreshReminders()
      root.rebuildDisplay()
    }
  }

  function refreshReminders() {
    if (listProc.running) return
    listProc.running = true
  }

  function loadReminders(raw) {
    var parsed = ({ reminders: [] })
    try { parsed = JSON.parse(String(raw || "{}")) } catch (e) { parsed = ({ reminders: [] }) }
    root.reminders = Array.isArray(parsed.reminders) ? parsed.reminders : []
    if (root.active && !root.setting) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    if (root.setting) return
    var needle = String(root.filterText || "").trim().toLowerCase()
    displayModel.clear()

    for (var i = 0; i < root.reminders.length; i++) {
      var item = root.reminders[i] || ({})
      var label = String(item.label || item.message || "Reminder")
      var detail = String(item.remaining || "") + (item.atTime ? "  •  " + item.atTime : "")
      var searchable = (label + " " + detail + " " + String(item.minutes || "")).toLowerCase()
      if (needle && searchable.indexOf(needle) < 0) continue
      displayModel.append({
        unit: String(item.unit || ""),
        label: label,
        detail: detail
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))
    root.cursorActive = displayModel.count > 0
    Qt.callLater(function() { root.revealCursor() })
  }

  function submit() {
    if (!root.setting) return
    var value = String(root.filterText || "")

    if (root.step === "minutes") {
      var nextMinutes = value.trim()
      if (!/^[0-9]+$/.test(nextMinutes) || Number(nextMinutes) <= 0) {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", "Invalid reminder", "Enter the number of minutes"])
        return
      }
      root.minutes = nextMinutes
      root.step = "message"
      root.filterRequested("")
      return
    }

    var args = [root.omarchyPath + "/bin/omarchy-reminder", root.minutes]
    if (value.length > 0) args.push(value)
    root.closeRequested()
    Quickshell.execDetached(args)
  }

  function backStep() {
    if (!root.setting || root.step !== "message") return false
    root.step = "minutes"
    root.filterRequested(root.minutes)
    return true
  }

  function revealCursor() {
    if (displayModel.count > 0)
      resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function disarmPointer() { pointerGate.reset() }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    root.revealCursor()
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    root.revealCursor()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function selectedRow() {
    return root.selectedIndex >= 0 && root.selectedIndex < displayModel.count
      ? displayModel.get(root.selectedIndex) : null
  }

  function requestDelete() {
    var row = root.selectedRow()
    if (!row) return
    root.confirmClear = false
    root.confirmUnit = row.unit
    root.confirmLabel = row.label
    confirmDialog.selectedIndex = 1
    root.confirmOpen = true
  }

  function requestClear() {
    if (root.reminders.length === 0) return
    root.confirmClear = true
    root.confirmUnit = ""
    root.confirmLabel = ""
    confirmDialog.selectedIndex = 1
    root.confirmOpen = true
  }

  function cancelConfirm() {
    root.confirmOpen = false
    root.confirmUnit = ""
    root.confirmLabel = ""
  }

  function confirmAction() {
    root.confirmOpen = false
    if (root.confirmClear) {
      actionProc.command = [root.omarchyPath + "/bin/omarchy-reminder", "clear"]
    } else {
      actionProc.command = [root.pluginDir + "/reminders.sh", "delete", root.confirmUnit, root.confirmLabel]
    }
    actionProc.running = true
  }

  function handleConfirmKey(event) {
    return confirmDialog.handleKey(event)
  }

  function debugRows() {
    var rows = []
    for (var i = 0; i < Math.min(displayModel.count, 12); i++) {
      var row = displayModel.get(i)
      rows.push({ label: row.label, detail: row.detail, unit: row.unit })
    }
    return rows
  }

  onActiveChanged: if (active) root.resetForOpen()
  onModeChanged: if (active) root.resetForOpen()
  onFilterTextChanged: if (active && !setting) {
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  ListModel { id: displayModel }

  Process {
    id: listProc
    command: [root.omarchyPath + "/bin/omarchy-reminder", "show", "--json"]
    stdout: StdioCollector { id: listOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadReminders(listOutput.text)
    }
  }

  Process {
    id: actionProc
    onExited: root.refreshReminders()
  }

  Timer {
    interval: 30000
    running: root.active && !root.setting
    repeat: true
    onTriggered: root.refreshReminders()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: root
  }

  ListView {
    id: resultList
    anchors.fill: parent
    visible: !root.setting
    model: displayModel
    clip: true
    spacing: Style.space(4)
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
      id: row
      required property int index
      required property string unit
      required property string label
      required property string detail

      readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

      width: ListView.view.width
      height: root.rowHeight
      radius: root.cornerRadius
      color: hasCursor ? root.selectedBackground : "transparent"

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: row.label
          textFormat: Text.PlainText
          color: row.hasCursor ? root.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: row.detail
          textFormat: Text.PlainText
          color: row.hasCursor ? root.selectedText : root.foreground
          opacity: 0.62
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.selectFromPointer(row.index, row, { x: rowMouse.mouseX, y: rowMouse.mouseY })
        onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width
    spacing: Style.space(8)
    visible: !root.setting && displayModel.count === 0

    Text {
      width: parent.width
      text: "󰢌"
      textFormat: Text.PlainText
      color: root.selectedText
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: root.reminders.length === 0 ? "No active reminders" : "No matches for “" + root.filterText + "”"
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
    }
  }

  SafeConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    opened: root.confirmOpen
    z: 20
    message: root.confirmClear ? "Delete all active reminders?" : "Delete “" + root.confirmLabel + "”?"
    confirmText: "Delete"
    background: root.background
    foreground: root.foreground
    scrim: Color.menu.scrim
    selectedBackground: root.selectedBackground
    selectedText: root.selectedText
    fontFamily: root.fontFamily
    cornerRadius: root.cornerRadius
    onCanceled: root.cancelConfirm()
    onConfirmed: root.confirmAction()
  }
}

import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "vendor/ClipboardHistory.js" as ClipboardHistory

// Clipboard history rendered inside the menu card. Omarchy's keep-loaded
// clipboard plugin remains the sole capture service; this view only watches
// its state file and delegates paste/open operations to the packaged helpers.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool active: false
  property string filterText: ""
  property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color borderColor: Color.menu.border
  property int cornerRadius: Style.cornerRadius
  property int rowHeight: Math.max(Style.space(48), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int contentMargin: Style.spacing.panelPadding
  property int historyLimit: 300
  property int displayLimit: 50

  property var history: []
  property int selectedIndex: 0
  property bool cursorActive: true
  property bool clearConfirmOpen: false

  readonly property int count: displayModel.count
  readonly property real contentY: resultList.contentY
  readonly property real originY: resultList.originY
  readonly property real scrollOffset: resultList.contentY - resultList.originY
  readonly property int historyCount: root.history.length

  signal closeRequested()

  function resetForOpen() {
    root.cancelClearHistory()
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    reopenScrollTimer.restart()
  }

  function resetTransient() {
    root.clearConfirmOpen = false
    root.disarmPointer()
  }

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    if (root.active) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, root.displayLimit)
    displayModel.clear()

    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))

    Qt.callLater(function() { root.revealCursor() })
  }

  function revealCursor() {
    if (displayModel.count === 0) return
    if (root.selectedIndex === 0) {
      resultList.cancelFlick()
      resultList.contentY = resultList.originY
      resultList.positionViewAtIndex(0, ListView.Beginning)
    }
    else resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
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
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex)
  }

  function activate(modifiers) {
    var row = root.selectedRow()
    if (!row) {
      if (displayModel.count > 0) root.cursorActive = true
      return
    }

    if (modifiers & Qt.AltModifier) root.openSelected(row)
    else if (modifiers & Qt.ShiftModifier) root.copySelected(row)
    else root.pasteSelected(row)
  }

  function pasteSelected(row) {
    if (!row) return
    var entryType = String(row.entryType || "")
    var mime = String(row.mime || "")
    var path = String(row.path || "")
    var historyIndex = Number(row.historyIndex)
    root.closeRequested()
    if (entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", mime, path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    var entryType = String(row.entryType || "")
    var mime = String(row.mime || "")
    var path = String(row.path || "")
    var historyIndex = Number(row.historyIndex)
    root.closeRequested()
    if (entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", mime, path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(historyIndex)])
    }
  }

  function openSelected(row) {
    if (!row) return
    var historyIndex = Number(row.historyIndex)
    root.closeRequested()
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(historyIndex)])
  }

  function removeSelected() {
    var row = root.selectedRow()
    if (!row) return

    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()
    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory()
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.clearConfirmOpen = false
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function handleConfirmKey(event) {
    return clearConfirm.handleKey(event)
  }

  function debugRows() {
    var rows = []
    for (var i = 0; i < Math.min(displayModel.count, 12); i++) {
      var row = displayModel.get(i)
      rows.push({ type: row.entryType, preview: row.previewText, historyIndex: row.historyIndex })
    }
    return rows
  }

  onFilterTextChanged: if (root.active) root.rebuildDisplay()
  onActiveChanged: {
    if (root.active) {
      historyFile.reload()
      root.resetForOpen()
    }
    else root.resetTransient()
  }

  Component.onCompleted: historyFile.reload()

  ListModel { id: displayModel }

  FileView {
    id: historyFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: root
  }

  // A reopened menu becomes visible after its model has already rebuilt.
  // Re-assert the saved selection once the ListView has real geometry so a
  // previous End/PageDown position cannot survive into the next summon.
  Timer {
    id: reopenScrollTimer
    interval: 50
    repeat: false
    onTriggered: root.revealCursor()
  }

  Row {
    anchors.fill: parent
    spacing: 0

    Item {
      width: parent.width / 2
      height: parent.height
      clip: true

      ListView {
        id: resultList
        anchors.fill: parent
        anchors.rightMargin: root.contentMargin
        model: displayModel
        clip: true
        spacing: Style.spacing.xs
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
          id: row
          required property int index
          required property string entryType
          required property string previewText
          required property string previewImage

          readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

          width: ListView.view.width
          height: root.rowHeight
          radius: root.cornerRadius
          color: hasCursor ? root.selectedBackground : "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.topMargin: Style.space(7)
            anchors.bottomMargin: Style.space(7)
            spacing: Style.space(9)

            Image {
              visible: row.previewImage.length > 0
              width: visible ? parent.height : 0
              height: parent.height
              source: row.previewImage
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
            }

            Text {
              visible: row.previewImage.length === 0
              width: visible ? parent.height : 0
              height: parent.height
              text: row.entryType === "file" ? "󰈔" : "󰅌"
              textFormat: Text.PlainText
              color: row.hasCursor ? root.selectedText : root.foreground
              opacity: 0.72
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            Text {
              width: parent.width - parent.height - parent.spacing
              height: parent.height
              text: row.previewText
              textFormat: Text.PlainText
              color: row.hasCursor ? root.selectedText : root.foreground
              opacity: row.entryType === "text" ? 1 : 0.72
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectFromPointer(row.index, row, { x: rowMouse.mouseX, y: rowMouse.mouseY })
            onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
            onClicked: {
              root.cursorActive = true
              root.selectedIndex = row.index
              root.activate(Qt.NoModifier)
            }
          }
        }
      }
    }

    Item {
      id: previewPane
      width: parent.width / 2
      height: parent.height
      clip: true

      readonly property var activeRow: displayModel.count > 0
        && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count
        ? displayModel.get(root.selectedIndex) : null

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.spacing.hairline
        color: Util.alpha(root.borderColor, 0.28)
      }

      Text {
        visible: previewPane.activeRow && !previewPane.activeRow.previewImage
        anchors.fill: parent
        anchors.leftMargin: root.contentMargin
        text: previewPane.activeRow ? previewPane.activeRow.fullText : ""
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        wrapMode: Text.WrapAnywhere
        elide: Text.ElideRight
        verticalAlignment: Text.AlignTop
      }

      Image {
        visible: previewPane.activeRow && previewPane.activeRow.previewImage
        anchors.fill: parent
        anchors.leftMargin: root.contentMargin
        source: previewPane.activeRow ? previewPane.activeRow.previewImage : ""
        fillMode: Image.PreserveAspectFit
        verticalAlignment: Image.AlignTop
        asynchronous: true
        smooth: true
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)
    visible: displayModel.count === 0

    Text {
      width: parent.width
      text: "󰅌"
      textFormat: Text.PlainText
      color: root.selectedText
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
    }
  }

  SafeConfirmDialog {
    id: clearConfirm
    anchors.fill: parent
    opened: root.clearConfirmOpen
    z: 20
    message: "Delete entire clipboard history?"
    confirmText: "Delete"
    background: root.background
    foreground: root.foreground
    scrim: Color.menu.scrim
    selectedBackground: root.selectedBackground
    selectedText: root.selectedText
    fontFamily: root.fontFamily
    cornerRadius: root.cornerRadius
    onCanceled: root.cancelClearHistory()
    onConfirmed: root.confirmClearHistory()
  }
}

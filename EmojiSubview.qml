import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "vendor/EmojiSearch.js" as EmojiSearch

// Native menu subview backed by Omarchy's packaged emoji catalog and insert
// helper. The catalog is parsed once; GridView creates only visible delegates,
// avoiding the stock overlay's 1,000 ListModel appends on every open.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool active: false
  property string filterText: ""
  property string fontFamily: Style.font.menuFamily
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property int cornerRadius: Style.cornerRadius

  property var emojis: []
  property var filteredEmojis: []
  property string appliedFilter: "__unloaded__"
  property int selectedIndex: 0
  property bool cursorActive: true
  property int resultLimit: 1000

  readonly property int count: filteredEmojis.length
  readonly property int cellWidth: Math.max(Style.space(48), Style.font.display + Style.spacing.md)
  readonly property int cellHeight: cellWidth
  readonly property int columns: Math.max(1, Math.floor(resultGrid.width / cellWidth))
  readonly property real scrollOffset: resultGrid.contentY - resultGrid.originY

  signal closeRequested()

  function loadEmojis(raw) {
    root.emojis = EmojiSearch.parseEmojis(raw)
    root.appliedFilter = "__unloaded__"
    if (root.active) root.rebuildDisplay()
  }

  function resetForOpen() {
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    reopenScrollTimer.restart()
  }

  function rebuildDisplay() {
    var normalizedFilter = String(root.filterText || "").trim().toLowerCase()
    if (normalizedFilter !== root.appliedFilter) {
      root.filteredEmojis = EmojiSearch.filterEmojis(root.emojis, normalizedFilter, root.resultLimit)
      root.appliedFilter = normalizedFilter
    }
    if (root.count === 0) root.selectedIndex = 0
    else root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.count - 1))
    root.cursorActive = root.count > 0
    Qt.callLater(function() { root.revealCursor() })
  }

  function revealCursor() {
    if (root.count === 0) return
    resultGrid.positionViewAtIndex(root.selectedIndex,
      root.selectedIndex === 0 ? GridView.Beginning : GridView.Contain)
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function select(delta) {
    if (root.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + root.count) % root.count
    root.revealCursor()
  }

  function selectRow(delta) {
    if (root.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex + delta * root.columns, root.count - 1))
    root.revealCursor()
  }

  function selectPage(delta) {
    var visibleRows = Math.max(1, Math.floor(resultGrid.height / root.cellHeight))
    root.selectAbsolute(root.selectedIndex + delta * root.columns * visibleRows)
  }

  function selectAbsolute(index) {
    if (root.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, root.count - 1))
    root.revealCursor()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activate() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= root.count) return
    var entry = root.filteredEmojis[root.selectedIndex]
    if (!entry || !entry.e) return
    root.closeRequested()
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-menu-emoji-insert", entry.e])
  }

  function debugRows() {
    var rows = []
    for (var i = 0; i < Math.min(root.count, 12); i++)
      rows.push({ emoji: root.filteredEmojis[i].e, keywords: root.filteredEmojis[i].k })
    return rows
  }

  onActiveChanged: if (active) root.resetForOpen()
  onFilterTextChanged: if (active) {
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  FileView {
    path: root.omarchyPath + "/shell/plugins/emojis/emojis.json"
    onLoaded: root.loadEmojis(text())
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: root
  }

  Timer {
    id: reopenScrollTimer
    interval: 50
    repeat: false
    onTriggered: root.revealCursor()
  }

  GridView {
    id: resultGrid
    anchors.fill: parent
    model: root.filteredEmojis
    clip: true
    cellWidth: root.cellWidth
    cellHeight: root.cellHeight
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
      id: cell
      required property int index
      required property var modelData

      readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

      width: root.cellWidth
      height: root.cellHeight
      radius: root.cornerRadius
      color: hasCursor ? root.selectedBackground : "transparent"

      Text {
        anchors.centerIn: parent
        text: cell.modelData.e
        textFormat: Text.PlainText
        color: cell.hasCursor ? root.selectedText : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      MouseArea {
        id: cellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.selectFromPointer(cell.index, cell, { x: cellMouse.mouseX, y: cellMouse.mouseY })
        onPositionChanged: function(mouse) { root.selectFromPointer(cell.index, cell, mouse) }
        onClicked: {
          root.cursorActive = true
          root.selectedIndex = cell.index
          root.activate()
        }
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)
    visible: root.count === 0

    Text {
      width: parent.width
      text: "󰞅"
      textFormat: Text.PlainText
      color: root.selectedText
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width
      text: root.emojis.length === 0 ? "Loading emojis…" : "No matches for “" + root.filterText + "”"
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
    }
  }
}

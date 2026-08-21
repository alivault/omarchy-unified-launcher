import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.alivault.omarchy-unified-launcher"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2318"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else if (root.bar.shell && typeof root.bar.shell.toggle === "function")
        root.bar.shell.toggle(root.moduleName, JSON.stringify({ menu: "root" }))
      else root.bar.run("omarchy-shell shell toggle io.github.alivault.omarchy-unified-launcher '{\"menu\":\"root\"}'")
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jonathan.gospel-of-the-day"
  ipcTarget: "jonathan.gospel-of-the-day"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string configuredLanguage: Model.normalizeLanguage(setting("language", ""))
  readonly property bool hasLanguage: configuredLanguage !== ""
  readonly property var configuredRite: Model.riteForLanguage(configuredLanguage)
  readonly property bool rtl: Model.isRtlLanguage(configuredLanguage)
  readonly property int contentAlign: rtl ? Text.AlignRight : Text.AlignLeft

  readonly property int innerWidth: Math.max(Style.space(348), bodyScroll && bodyScroll.width > 0 ? bodyScroll.width : Style.space(348))
  readonly property int rowHeight: Style.space(36)
  readonly property int tabHeight: Style.space(32)

  property string pickerMode: "rite"
  property string pickerRite: ""
  property int pickerCursor: 0
  readonly property bool choosing: pickerMode !== ""
  readonly property var pickerModel: pickerMode === "language"
    ? Model.languagesForRite(pickerRite)
    : Model.riteList()
  property int activeTab: 1
  property var day: null
  property bool loading: false
  property string lastError: ""
  property date today: new Date()
  property date viewDate: new Date()

  readonly property bool viewingToday: Model.isSameDay(viewDate, today)
  readonly property bool canGoBack: Model.canStepDate(viewDate, today, -1)
  readonly property bool canGoForward: Model.canStepDate(viewDate, today, 1)
  readonly property string viewDateKey: Model.isoDate(viewDate)

  readonly property var tabLabels: ["Readings", "Gospel", "Commentary"]
  readonly property string liturgicalTitle: day ? String(day.liturgicalTitle || "") : ""
  readonly property string saint: day ? String(day.saint || "") : ""
  readonly property string dayDate: day ? String(day.date || "") : ""
  readonly property var readings: day && day.readings ? day.readings : []
  readonly property var gospel: day && day.gospel ? day.gospel : { kind: "gospel", title: "", reference: "", text: "" }
  readonly property var commentary: day && day.commentary ? day.commentary : { available: false, title: "", author: "", source: "", text: "" }

  function pluginFile(rel) {
    var url = String(Qt.resolvedUrl(rel))
    if (url.indexOf("file://") === 0) {
      var path = decodeURIComponent(url.substring(7))
      if (path.length > 0 && path.charAt(0) !== "/") path = "/" + path
      return path
    }
    return url
  }

  function open() {
    root.today = new Date()
    root.viewDate = root.today
    root.pickerMode = root.hasLanguage ? "" : "rite"
    root.pickerCursor = 0
    if (root.hasLanguage) root.loadDay()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function showRitePicker() {
    root.pickerCursor = Model.riteIndex(root.configuredRite.code)
    root.pickerMode = "rite"
  }

  function showLanguagePicker(riteCode) {
    root.pickerRite = riteCode || root.configuredRite.code
    root.pickerCursor = Model.languageIndexInRite(root.pickerRite, root.configuredLanguage)
    root.pickerMode = "language"
  }

  function movePickerCursor(delta) {
    var next = root.pickerCursor + delta
    if (next < 0) next = 0
    if (next > root.pickerModel.length - 1) next = root.pickerModel.length - 1
    root.pickerCursor = next
  }

  function selectRite(riteCode) {
    var rite = Model.riteEntry(riteCode)
    if (rite.languages.length === 1) return root.selectLanguage(rite.languages[0].code)
    var match = root.hasLanguage ? Model.matchLanguageInRite(rite.code, root.configuredLanguage) : ""
    if (match !== "") return root.selectLanguage(match)
    root.showLanguagePicker(rite.code)
  }

  function selectLanguage(code) {
    var normalized = Model.normalizeLanguage(code)
    if (normalized === "") return
    var changed = normalized !== root.configuredLanguage
    if (changed) persistSettings({ language: normalized })
    root.pickerMode = ""
    if (changed) root.day = null
    root.loadDay(normalized)
  }

  function selectAtCursor() {
    if (root.pickerCursor < 0 || root.pickerCursor >= root.pickerModel.length) return
    var entry = root.pickerModel[root.pickerCursor]
    if (root.pickerMode === "rite") root.selectRite(entry.code)
    else root.selectLanguage(entry.code)
  }

  function setTab(index) {
    if (index < 0 || index > 2) return
    root.activeTab = index
    if (bodyScroll) bodyScroll.contentY = 0
  }

  function scrollContent(delta) {
    if (!bodyScroll) return
    var step = Style.space(48)
    var maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height)
    bodyScroll.contentY = Math.max(0, Math.min(maxY, bodyScroll.contentY + (delta * step)))
  }

  function formattedDate(value) {
    if (!value) return ""
    var parts = String(value).split("-")
    if (parts.length !== 3) return String(value)
    return Qt.formatDate(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])), "MMMM d, yyyy")
  }

  function loadDay(lang, forceRefresh) {
    var code = Model.normalizeLanguage(lang || root.configuredLanguage)
    if (code === "") return
    if (fetchProc.running) fetchProc.running = false
    root.loading = true
    root.lastError = ""
    var command = [root.pluginFile("scripts/run-helper.sh"), "--lang", code, "--date", root.viewDateKey]
    if (forceRefresh) command.push("--refresh")
    fetchProc.command = command
    fetchProc.running = true
  }

  function moveDay(delta) {
    var next = Model.clampViewDate(Model.addDays(root.viewDate, delta), root.today)
    if (Model.isSameDay(next, root.viewDate)) return
    root.viewDate = next
    root.loadDay()
  }

  function goToToday() {
    root.today = new Date()
    if (Model.isSameDay(root.viewDate, root.today)) return
    root.viewDate = root.today
    root.loadDay()
  }

  function refresh() {
    if (root.hasLanguage) root.loadDay(root.configuredLanguage, true)
  }

  function copyVisible() {
    if (root.choosing || !root.day) return
    var text = Model.copyText(root.day, root.activeTab)
    if (text === "") return
    Quickshell.execDetached(["wl-copy", "--", text])
  }

  function applyFetch(exitCode) {
    var raw = String(fetchOut.text || "")
    var parsed = Model.parsePayload(raw)
    root.loading = false
    if (parsed) {
      root.day = parsed
      root.lastError = ""
      return
    }
    if (root.day && String(root.day.date) !== root.viewDateKey)
      root.day = null
    root.lastError = String(fetchErr.text || "").replace(/^\s+|\s+$/g, "") || "Could not load readings"
  }

  function pickerEntryAt(index) {
    if (!root.pickerModel || index < 0 || index >= root.pickerModel.length)
      return { code: "", name: "" }
    return root.pickerModel[index]
  }

  function pickerEntryDetail(entry) {
    if (root.pickerMode !== "rite") return String(entry.code || "")
    var langs = entry.languages || []
    if (langs.length === 1) return langs[0].name
    return langs.length + " languages"
  }

  function readingAt(index) {
    if (index < 0 || index >= root.readings.length)
      return { kind: "", title: "", reference: "", text: "" }
    return root.readings[index]
  }

  component BodyText: Column {
    id: bodyText
    property string text: ""
    spacing: Style.space(6)
    topPadding: Style.space(8)

    Repeater {
      model: bodyText.text.split("\n").map(function(p) { return p.trim() }).filter(function(p) { return p !== "" })

      SelectableText {
        required property string modelData
        width: bodyText.width
        text: modelData
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: root.contentAlign
      }
    }
  }

  Process {
    id: fetchProc
    running: false
    command: []
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    stderr: StdioCollector { id: fetchErr; waitForEnd: true }
    onExited: function(exitCode) { root.applyFetch(exitCode) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(Math.max(bodyColumn.implicitHeight, Style.space(400)), panel.availableCardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.choosing) {
          if (dy !== 0) root.movePickerCursor(dy)
          return
        }
        if (dy !== 0) root.scrollContent(dy)
        else if (dx !== 0) root.showLanguagePicker()
      }
      onActivateRequested: {
        if (root.choosing) root.selectAtCursor()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "1") root.setTab(0)
        else if (t === "2") root.setTab(1)
        else if (t === "3") root.setTab(2)
        else if (t === "l" || t === "L") root.showLanguagePicker()
        else if (t === "r" || t === "R") root.showRitePicker()
        else if (t === "[" ) root.moveDay(-1)
        else if (t === "]" ) root.moveDay(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "u" || t === "U") root.refresh()
        else if (t === "c" || t === "C") root.copyVisible()
      }

      Flickable {
        id: bodyScroll
        anchors.fill: parent
        contentWidth: bodyColumn.width
        contentHeight: bodyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: bodyColumn
          width: Math.max(bodyScroll.width, root.innerWidth)
          spacing: Style.space(12)

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            text: "✝"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: 40
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pickerMode === "rite" ? "Choose a rite"
              : root.pickerMode === "language" ? "Choose a language"
              : (root.liturgicalTitle || "Gospel of the Day")
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.choosing && root.saint !== ""
            text: root.saint
            color: Qt.darker(root.contentForeground, 1.35)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            horizontalAlignment: root.contentAlign
          }

          Item {
            visible: root.hasLanguage
            width: root.innerWidth
            height: visible ? dateNav.height : 0
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
              id: dateNav
              width: parent.width
              height: dateLabel.implicitHeight + Style.space(10)

              PanelActionButton {
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous day"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: root.canGoBack
                opacity: enabled ? 1 : 0.35
                onClicked: root.moveDay(-1)
              }

              Text {
                id: dateLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(180)
                horizontalAlignment: Text.AlignHCenter
                text: root.formattedDate(root.viewDateKey)
                color: Qt.darker(root.contentForeground, 1.35)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next day"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: root.canGoForward
                opacity: enabled ? 1 : 0.35
                onClicked: root.moveDay(1)
              }
            }
          }

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.hasLanguage && !root.viewingToday
            text: "Today"
            color: Style.hoverStateColor(root.contentForeground, Color.accent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()
            }
          }

          Item {
            visible: root.hasLanguage
            width: root.innerWidth
            height: visible ? root.rowHeight : 0
            anchors.horizontalCenter: parent.horizontalCenter

            readonly property real chipWidth: ((copyButton.visible ? copyButton.x : refreshButton.x) - Style.space(8) * 2) / 2

            Rectangle {
              id: riteChip
              anchors.left: parent.left
              width: parent.chipWidth
              height: parent.height
              radius: Style.cornerRadius
              color: riteChipMouse.containsMouse
                ? Style.hoverFillFor(root.contentForeground, Color.accent)
                : "transparent"
              border.width: Style.spacing.hairline
              border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.configuredRite.short
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: riteChipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.pickerMode === "rite") root.pickerMode = ""
                  else root.showRitePicker()
                }
              }
            }

            Rectangle {
              id: langChip
              anchors.left: riteChip.right
              anchors.leftMargin: Style.space(8)
              anchors.right: copyButton.visible ? copyButton.left : refreshButton.left
              anchors.rightMargin: Style.space(8)
              height: parent.height
              radius: Style.cornerRadius
              color: langChipMouse.containsMouse
                ? Style.hoverFillFor(root.contentForeground, Color.accent)
                : "transparent"
              border.width: Style.spacing.hairline
              border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: Model.languageLabel(root.configuredLanguage)
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: langChipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.pickerMode === "language") root.pickerMode = ""
                  else root.showLanguagePicker()
                }
              }
            }

            PanelActionButton {
              id: copyButton
              visible: root.hasLanguage && !root.choosing && !!root.day
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰆏"
              tooltipText: "Copy"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              enabled: !!root.day
              onClicked: root.copyVisible()
            }

            PanelActionButton {
              id: refreshButton
              visible: root.hasLanguage
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑓"
              tooltipText: "Refresh"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              enabled: !root.loading
              onClicked: root.refresh()
            }
          }

          Column {
            visible: root.choosing
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            Repeater {
              model: root.choosing ? root.pickerModel.length : 0

              Rectangle {
                required property int index
                readonly property var entry: root.pickerEntryAt(index)

                width: root.innerWidth
                height: root.rowHeight
                radius: Style.cornerRadius
                color: (root.pickerCursor === index || pickerMouse.containsMouse)
                  ? Style.hoverFillFor(root.contentForeground, Color.accent)
                  : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: entry.name
                  color: root.pickerCursor === index
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.pickerEntryDetail(entry)
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                MouseArea {
                  id: pickerMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.pickerCursor = index
                  onClicked: {
                    root.pickerCursor = index
                    root.selectAtCursor()
                  }
                }
              }
            }
          }

          Row {
            id: tabRow
            visible: !root.choosing
            width: root.innerWidth
            height: visible ? root.tabHeight : 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            Repeater {
              model: root.tabLabels

              Rectangle {
                required property int index
                required property string modelData

                width: (root.innerWidth - tabRow.spacing * 2) / 3
                height: root.tabHeight
                radius: Style.cornerRadius
                color: (root.activeTab === index || tabMouse.containsMouse)
                  ? Style.hoverFillFor(root.contentForeground, Color.accent)
                  : "transparent"
                border.width: root.activeTab === index ? Style.spacing.hairline : 0
                border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: root.activeTab === index
                    ? Style.hoverStateColor(root.contentForeground, Color.accent)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setTab(index)
                }
              }
            }
          }

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.choosing && root.loading && !root.day
            text: "Loading…"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            visible: !root.choosing && root.lastError !== ""
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: root.day ? "Showing saved copy. " + root.lastError : root.lastError
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: parent.width
              text: root.loading ? "Retrying…" : "Retry"
              color: Style.hoverStateColor(root.contentForeground, Color.accent)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter

              MouseArea {
                anchors.fill: parent
                enabled: !root.loading
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
          }

          Repeater {
            model: (!root.choosing && root.activeTab === 0) ? root.readings.length : 0

            Column {
              required property int index
              readonly property var entry: root.readingAt(index)
              width: root.innerWidth
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)

              SelectableText {
                width: parent.width
                visible: entry.title !== "" || entry.reference !== ""
                text: entry.title !== "" ? entry.title : entry.reference
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
              }

              SelectableText {
                width: parent.width
                visible: entry.title !== "" && entry.reference !== "" && entry.reference !== entry.title
                text: entry.reference
                color: Qt.darker(root.contentForeground, 1.45)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
              }

              BodyText {
                width: parent.width
                text: entry.text
              }
            }
          }

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.choosing && root.activeTab === 0 && !root.loading && root.day && root.readings.length === 0
            text: "No readings today"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            visible: !root.choosing && root.activeTab === 1 && !root.loading
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            SelectableText {
              width: parent.width
              visible: root.gospel.title !== "" || root.gospel.reference !== ""
              text: root.gospel.title !== "" ? root.gospel.title : root.gospel.reference
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            SelectableText {
              width: parent.width
              visible: root.gospel.title !== "" && root.gospel.reference !== "" && root.gospel.reference !== root.gospel.title
              text: root.gospel.reference
              color: Qt.darker(root.contentForeground, 1.45)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            BodyText {
              width: parent.width
              visible: root.gospel.text !== ""
              text: root.gospel.text
            }

            Text {
              width: parent.width
              visible: root.gospel.text === "" && !!root.day
              text: "No gospel today"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            visible: !root.choosing && root.activeTab === 2 && !root.loading
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            SelectableText {
              width: parent.width
              visible: root.commentary.title !== ""
              text: root.commentary.title
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            SelectableText {
              width: parent.width
              visible: Model.commentaryByline(root.commentary) !== ""
              text: Model.commentaryByline(root.commentary)
              color: Qt.darker(root.contentForeground, 1.45)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            BodyText {
              width: parent.width
              visible: root.commentary.available
              text: root.commentary.text
            }

            Text {
              width: parent.width
              visible: !root.commentary.available && !!root.day
              text: "No commentary today"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Text {
            width: root.innerWidth
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Evangelizo.org"
            color: Qt.darker(root.contentForeground, 1.55)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}

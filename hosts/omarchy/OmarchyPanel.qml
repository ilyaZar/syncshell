import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ui"
import "models/PanelModel.js" as PanelModel

Panel {
  id: root

  ipcTarget: moduleName

  readonly property var syncthing: bar && bar.shell && moduleName
    ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color warning: "#ebcb8b"
  readonly property color success: "#a3be8c"
  readonly property color syncthingBlue: "#26B6DB"
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string homePath: Quickshell.env("HOME")
  readonly property string folderPickerScript: localPathFromUrl(
    Qt.resolvedUrl("scripts/syncthing-folder-picker.sh"))
  readonly property bool folderPickerRunning: folderPickerProcess.running
  property bool moreOpen: false
  property bool settingsMenuOpen: false
  property bool removalConfirmOpen: false
  property int settingsSelectedIndex: 0
  property bool addOpen: false
  property bool addIdEdited: false
  property bool addLabelFromOffer: false
  property bool addSubmissionPending: false
  property bool preserveStateForFolderPicker: false
  property string selectedFolderId: ""
  property string selectedPendingOffer: ""
  property string forgetFolderId: ""
  property bool forgetConfirmOpen: false
  property string folderPickerOutput: ""
  property string folderPickerError: ""
  property string displayedNotice: ""
  property bool noticeShown: false
  readonly property var folderRows: buildFolderRows()
  readonly property bool compactFolders: folderRows.length >= 5
  readonly property string displayedFolderId: compactFolders
    && visibleSyncActivity !== "" && syncthing
    && folderById(syncthing.syncActivityFolderId)
    ? syncthing.syncActivityFolderId : selectedFolderId
  readonly property var visibleFolderRows: compactFolders
    ? (folderById(displayedFolderId) ? [folderById(displayedFolderId)] : [])
    : folderRows
  readonly property var pendingOfferRows: pendingOfferOptions()
  readonly property double trackedBytes: folderTotal("globalBytes")
  readonly property int trackedFiles: folderTotal("globalFiles")
  readonly property int scanningFolderCount: folderStateCount("scanning")
  readonly property int pausedFolderCount: folderStateCount("paused")
  readonly property int rescannableFolderCount:
    Math.max(0, folderRows.length - pausedFolderCount)
  readonly property bool syncInProgress: syncthing
    ? syncthing.syncingFolderCount > 0 || scanningFolderCount > 0
      || syncthing.syncingFiles.length > 0
    : false
  readonly property bool busy: syncthing
    ? syncthing.refreshing || syncInProgress
    : false
  readonly property bool hasProblems: syncthing
    ? syncthing.folderProblemCount > 0 : false
  readonly property string iconVariant: {
    if (!syncthing || !syncthing.canUseRuntime) return "notify"
    if (syncthing.serviceAvailable && !syncthing.serviceActive) return "pause"
    if (syncthing.phase === "error" || hasProblems) return "notify"
    if (busy) return "sync"
    return "default"
  }
  readonly property bool legacyThemedIcon:
    setting("themedIcon", false) === true
  readonly property bool themedIcon: syncthing
    ? syncthing.iconStyle === "themed" : legacyThemedIcon
  readonly property url syncthingIconSource: Qt.resolvedUrl(
    "../../assets/status-" + iconVariant + ".svg")
  readonly property url themedIconSource: Qt.resolvedUrl(
    "../../assets/mono/status-" + iconVariant + ".svg")
  readonly property string tooltip: {
    if (!syncthing) return "Syncthing unavailable"
    if (iconVariant === "sync" && syncInProgress) {
      return "Syncthing: Sync in progress..."
    }
    return "Syncthing: " + syncthing.summaryText
  }
  readonly property string toggleHint: syncthing && syncthing.serviceActive
    ? "Stop syncing" : "Start syncing"
  readonly property string visibleError: {
    if (folderPickerError) return folderPickerError
    if (!syncthing) return ""
    return syncthing.folderMutationError || syncthing.controlError
      || syncthing.packageError
      || syncthing.settingsError
      || syncthing.lastError || ""
  }
  readonly property string visibleNotice: syncthing
    ? syncthing.folderMutationNotice || syncthing.settingsNotice : ""
  readonly property string visibleWarning: syncthing
    ? syncthing.recoveryWarning || syncthing.serviceStateWarning : ""
  readonly property bool serviceStateDialogOpen: syncthing
    && syncthing.serviceStateDrift
  readonly property string visibleSyncActivity: syncthing
    ? syncthing.syncActivity : ""
  readonly property string visibleSyncDots: syncthing
    ? syncthing.syncActivityDots : ""
  readonly property string visibleSyncAction: syncthing
    ? syncthing.syncActivityAction : ""
  readonly property string visibleSyncDetail: syncthing
    ? syncthing.syncActivityDetail : ""
  readonly property string localDeviceName: PanelModel.localDeviceName(
    syncthing, Quickshell.env("HOSTNAME"))

  function showNotice(message) {
    displayedNotice = message
    noticeShown = true
    noticeFadeTimer.stop()
    noticeDisplayTimer.restart()
  }

  function copyToClipboard(value, notice) {
    var text = String(value || "")
    if (!text) return
    Quickshell.execDetached(["wl-copy", "--", text])
    showNotice(notice)
  }

  function copyLocalDeviceId() {
    copyToClipboard(syncthing ? syncthing.displayDeviceId : "",
      "Host ID copied")
  }

  function copyFolderId(folderId) {
    copyToClipboard(folderId, "Folder ID copied")
  }

  function chooseServiceStateAction(index) {
    if (syncthing) syncthing.chooseServiceStateAction(index)
  }

  function configureService() {
    if (!syncthing) return
    syncthing.setRefreshInterval(setting("refreshIntervalSec", 60))
    syncthing.setLegacyThemedIcon(legacyThemedIcon)
  }

  function buildFolderRows() {
    return PanelModel.buildFolderRows(syncthing, homePath)
  }

  function folderTotal(key) {
    return PanelModel.total(folderRows, key)
  }

  function folderStateCount(key) {
    return PanelModel.stateCount(folderRows, key)
  }

  function formatCount(value) {
    return PanelModel.formatCount(value)
  }

  function formatBytes(value) {
    return PanelModel.formatBytes(value)
  }

  function folderMeta(folder) {
    return PanelModel.folderMeta(folder, folderRescanning(folder))
  }

  function folderState(folder) {
    return PanelModel.folderState(folder,
      syncthing ? syncthing.recentlyLinkedFolderId : "",
      folderHasActivity(folder), folderRescanning(folder))
  }

  function folderStateColor(folder) {
    var state = folderState(folder)
    if (state === "UNLINKED") return warning
    if (state === "RESCANNING") return warning
    if (state === "SYNCING") return warning
    if (state === "ERROR") return urgent
    return success
  }

  function folderHasActivity(folder) {
    return folder && syncthing && visibleSyncActivity !== ""
      && syncthing.syncActivityFolderId === folder.id
  }

  function folderRescanning(folder) {
    if (!folder || !syncthing || folder.paused) return false
    if (folder.scanning) return true
    if (!syncthing.folderMutationBusy) return false
    if (syncthing.folderMutationAction === "rescan-all") return true
    return syncthing.folderMutationAction === "rescan"
      && syncthing.folderMutationId === String(folder.id || "")
  }

  function selectedFolder() {
    return folderById(selectedFolderId)
  }

  function folderById(folderId) {
    return PanelModel.folderById(folderRows, folderId)
  }

  function ensureFolderSelection() {
    if (selectedFolder()) return
    selectedFolderId = folderRows.length > 0 ? folderRows[0].id : ""
  }

  function selectFolderOffset(offset) {
    if (folderRows.length < 2 || offset === 0) return
    var current = selectedFolder()
    var index = current ? folderRows.indexOf(current) : 0
    index = (index + (offset > 0 ? 1 : -1) + folderRows.length)
      % folderRows.length
    selectedFolderId = folderRows[index].id
  }

  function folderOptions() {
    return PanelModel.folderOptions(folderRows, homePath)
  }

  function deviceName(deviceId) {
    var devices = syncthing && syncthing.devices ? syncthing.devices : []
    return PanelModel.deviceName(devices, deviceId)
  }

  function deviceOptions() {
    return PanelModel.deviceOptions(syncthing)
  }

  function pendingOfferOptions() {
    return PanelModel.pendingOfferOptions(syncthing)
  }

  function pendingFolderOptions() {
    var options = [{ value: "", label: "Create a new folder identity" }]
    for (var i = 0; i < pendingOfferRows.length; i++) {
      options.push({
        value: pendingOfferRows[i].value,
        label: "Accept " + pendingOfferRows[i].label
      })
    }
    return options
  }

  function ensurePendingOfferSelection() {
    for (var i = 0; i < pendingOfferRows.length; i++) {
      if (pendingOfferRows[i].value === selectedPendingOffer) return
    }
    selectedPendingOffer = pendingOfferRows.length > 0
      ? pendingOfferRows[0].value : ""
  }

  function encryptedPendingOfferCount() {
    return PanelModel.encryptedPendingOfferCount(syncthing)
  }

  function pathLabel(path) {
    return PanelModel.pathLabel(path)
  }

  function pathParentName(path) {
    return PanelModel.pathParentName(path, homePath)
  }

  function localPathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function openAddFolder() {
    if (!syncthing || !syncthing.online || syncthing.folderMutationBusy) return
    syncthing.clearFolderMutationMessage()
    addOpen = true
    addIdEdited = false
    addLabelFromOffer = false
    addSubmissionPending = false
    popup.resetAddForm()
    syncthing.requestFolderIdSuggestion()
    Qt.callLater(function() { popup.focusAddPath() })
  }

  function closeAddFolder() {
    if (syncthing && syncthing.folderMutationBusy
        && syncthing.folderMutationAction === "add") return
    addOpen = false
    addSubmissionPending = false
    popup.focusPanel()
  }

  function resetTransientState() {
    moreOpen = false
    settingsMenuOpen = false
    removalConfirmOpen = false
    addOpen = false
    addIdEdited = false
    addLabelFromOffer = false
    addSubmissionPending = false
    forgetFolderId = ""
    forgetConfirmOpen = false
    folderPickerError = ""
    popup.closeTransientPopups()
  }

  function applyPendingFolder(value) {
    var selected = String(value || "")
    popup.selectedDeviceIds = []
    if (!selected) {
      addIdEdited = false
      popup.addIdText = ""
      if (addLabelFromOffer) popup.addLabelText = ""
      addLabelFromOffer = false
      if (syncthing) syncthing.requestFolderIdSuggestion()
      return
    }
    var choice
    try {
      choice = JSON.parse(selected)
    } catch (error) {
      return
    }
    if (!(choice instanceof Array) || choice.length !== 2) return
    var id = String(choice[0] || "")
    var deviceId = String(choice[1] || "")
    var pending = syncthing && syncthing.pendingFolders
      ? syncthing.pendingFolders[id] || ({}) : ({})
    var offeredBy = pending.offeredBy || ({})
    var offer = offeredBy[deviceId] || ({})
    addIdEdited = true
    popup.addIdText = id
    popup.addLabelText = String(offer.label || id)
    addLabelFromOffer = true
    popup.selectedDeviceIds = deviceId ? [deviceId] : []
  }

  function acceptPendingFolderOffer(value) {
    var selected = String(value || "")
    if (!selected) return
    openAddFolder()
    if (!addOpen) return
    popup.pendingFolderValue = selected
    applyPendingFolder(selected)
    popup.scrollToTop()
    Qt.callLater(function() { popup.focusAddPath() })
  }

  function selectedPendingDeviceId() {
    var value = String(popup.pendingFolderValue || "")
    if (!value) return ""
    try {
      var choice = JSON.parse(value)
      if (!(choice instanceof Array) || choice.length !== 2) return ""
      var deviceId = String(choice[1] || "")
      return popup.selectedDeviceIds.indexOf(deviceId) >= 0 ? deviceId : ""
    } catch (error) {
      return ""
    }
  }

  function submitAddFolder() {
    if (!syncthing || syncthing.folderMutationBusy) return
    var label = String(popup.addLabelText || "").trim()
    if (!label) label = pathLabel(popup.addPathText)
    selectedFolderId = String(popup.addIdText || "").trim()
    addSubmissionPending = syncthing.addFolder(
      popup.addPathText,
      label,
      popup.addIdText,
      popup.selectedDeviceIds,
      selectedPendingDeviceId())
  }

  function requestForget(folder) {
    if (!folder || !folder.paused || !syncthing
        || syncthing.folderMutationBusy) return
    selectedFolderId = folder.id
    forgetFolderId = folder.id
    forgetConfirmOpen = true
  }

  function confirmForget() {
    forgetConfirmOpen = false
    if (syncthing) syncthing.forgetFolder(forgetFolderId)
    forgetFolderId = ""
  }

  function openWebUi() {
    if (syncthing && syncthing.online) Qt.openUrlExternally(syncthing.baseUrl)
  }

  function openSettingsMenu() {
    closeTransientViews()
    settingsSelectedIndex = 0
    settingsMenuOpen = true
    Qt.callLater(function() { popup.focusPanel() })
  }

  function closeSettingsMenu() {
    removalConfirmOpen = false
    settingsMenuOpen = false
    popup.focusPanel()
  }

  function closeTransientViews() {
    moreOpen = false
    addOpen = false
    forgetConfirmOpen = false
    popup.closeTransientPopups()
  }

  function moveSettingsSelection(offset) {
    settingsSelectedIndex = (settingsSelectedIndex
      + (offset > 0 ? 1 : 2)) % 3
  }

  function activateSettingsSelection() {
    if (settingsSelectedIndex === 0) {
      settingsMenuOpen = false
      if (syncthing) syncthing.openSettings()
    } else if (settingsSelectedIndex === 1) {
      removalConfirmOpen = true
    } else closeSettingsMenu()
  }

  function requestSelfRemoval(deletePluginSettings) {
    if (!syncthing) return
    syncthing.requestSelfRemoval(deletePluginSettings)
  }

  function openFolder(folder) {
    var path = resolveFolderPath(folder ? folder.path : "")
    if (!path) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", path])
  }

  function browseForFolder() {
    if (folderPickerProcess.running) return
    folderPickerOutput = ""
    folderPickerError = ""
    folderPickerProcess.command = ["bash", folderPickerScript]
    preserveStateForFolderPicker = true
    close()
    folderPickerProcess.running = true
  }

  function resolveFolderPath(value) {
    var path = String(value || "")
    if (path === "~") return homePath
    if (path.indexOf("~/") === 0) return homePath + path.slice(1)
    if (path.charAt(0) === "/" || !homePath) return path
    return homePath + "/" + path
  }

  function toggleSyncing() {
    if (syncthing && syncthing.canControlService
        && !syncthing.serviceActionRunning) syncthing.toggleService()
  }

  function installationAction() {
    if (syncthing && syncthing.installationState === "missing") {
      syncthing.installSyncthing()
    }
  }

  onSyncthingChanged: configureService()
  onSettingsChanged: configureService()
  onFolderRowsChanged: ensureFolderSelection()
  onPendingOfferRowsChanged: ensurePendingOfferSelection()
  onVisibleNoticeChanged: {
    if (visibleNotice !== "") {
      showNotice(visibleNotice)
    } else if (displayedNotice !== "") {
      noticeDisplayTimer.stop()
      noticeShown = false
      noticeFadeTimer.restart()
    }
  }
  onOpenedChanged: {
    if (opened) {
      if (syncthing) syncthing.refresh()
      ensureFolderSelection()
      popup.scrollToTop()
      Qt.callLater(function() { popup.focusPanel() })
    } else if (!preserveStateForFolderPicker) {
      resetTransientState()
    }
  }
  Component.onCompleted: configureService()

  Timer {
    id: noticeDisplayTimer
    interval: 10000
    repeat: false
    onTriggered: {
      root.noticeShown = false
      noticeFadeTimer.restart()
    }
  }

  Timer {
    id: noticeFadeTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.noticeShown) return
      var expired = root.displayedNotice
      root.displayedNotice = ""
      if (root.syncthing
          && root.syncthing.folderMutationNotice === expired) {
        root.syncthing.clearFolderMutationNotice()
      }
      if (root.syncthing
          && root.syncthing.settingsNotice === expired) {
        root.syncthing.clearSettingsNotice()
      }
    }
  }

  Connections {
    target: root.syncthing

    function onFolderIdSuggestionChanged() {
      if (root.addOpen && !root.addIdEdited
          && popup.pendingFolderValue === "") {
        popup.addIdText = root.syncthing.folderIdSuggestion
      }
    }

    function onFolderMutationNoticeChanged() {
      if (root.addSubmissionPending
          && root.syncthing.folderMutationNotice !== "") {
        root.addOpen = false
        root.addSubmissionPending = false
        popup.focusPanel()
      }
    }

    function onFolderMutationErrorChanged() {
      if (root.syncthing.folderMutationError !== "") {
        root.addSubmissionPending = false
      }
    }

  }

  Process {
    id: folderPickerProcess
    command: []

    stdout: StdioCollector {
      id: folderPickerStdout
      waitForEnd: true
      onStreamFinished: root.folderPickerOutput = text
    }

    onExited: function(exitCode) {
      var selected = String(root.folderPickerOutput
        || folderPickerStdout.text || "").trim()
      if (exitCode === 0 && selected) {
        var path = root.localPathFromUrl(selected)
        popup.addPathText = path
        if (!popup.addLabelText) popup.addLabelText = root.pathLabel(path)
      } else if (exitCode !== 0) {
        root.folderPickerError = "Folder chooser failed; enter the path manually."
      }
      Qt.callLater(function() {
        root.preserveStateForFolderPicker = false
        root.open()
        if (root.addOpen) {
          Qt.callLater(function() { popup.focusAddPath() })
        }
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        opacity: root.syncthing && root.syncthing.online ? 1.0 : 0.55

        // Keep the effect warm under the brand icon for reliable live switches.
        MonoIcon {
          anchors.centerIn: parent
          width: Style.space(12)
          height: width
          source: root.themedIconSource
          tint: root.foreground
        }

        Image {
          anchors.centerIn: parent
          width: Style.space(12)
          height: width
          source: root.syncthingIconSource
          sourceSize.width: 32
          sourceSize.height: 32
          fillMode: Image.PreserveAspectFit
          smooth: true
          visible: !root.themedIcon
        }
      }
    }
    active: root.hasProblems
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.syncthing) root.syncthing.refresh()
      else root.toggle()
    }
  }

  SyncthingPanelPopup {
    id: popup
    anchorItem: button
    controller: root
    owner: root
    bar: root.bar
    open: root.opened
  }

}

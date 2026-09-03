import QtQuick
import Quickshell
import qs.Commons
import "../../shared"
import "controllers"
import "models/FacadeModel.js" as FacadeModel

QtObject {
  id: root

  readonly property string pluginRoot: localPath(Qt.resolvedUrl("../.."))
  readonly property var state: core.snapshot || ({})
  readonly property var connection: state.connection || ({})
  readonly property var identity: state.identity || ({})
  readonly property var lifecycle: state.lifecycle || ({})
  readonly property var activity: state.activity || ({})
  readonly property var currentActivity: activity.current || ({})
  readonly property var webUi: state.webUi || ({})
  readonly property var coreInstallation: state.installation || ({})
  readonly property var counts: state.counts || ({})
  readonly property var lifecyclePresentation:
    FacadeModel.lifecyclePresentation(lifecycle)

  readonly property string phase: core.starting ? "core-starting"
    : core.incompatible ? "core-incompatible"
    : core.unavailable && !core.running ? "core-unavailable"
    : String(connection.phase || "discovering")
  readonly property bool online: connection.online === true
  property bool refreshing: false
  readonly property string lastError: core.lastError
    || String(connection.error && connection.error.message || "")
  readonly property string recoveryWarning: core.starting
    ? "Starting native core" : ""
  readonly property string baseUrl: String(webUi.url || "")
  readonly property string localDeviceId: String(identity.deviceId || "")
  readonly property string displayDeviceId: localDeviceId
    || identityState.localDeviceId
  readonly property string displayDeviceName: currentLocalDeviceName()
    || identityState.localDeviceName
  readonly property var connections: FacadeModel.connections(state.devices)
  readonly property var devices: FacadeModel.devices(state.devices)
  readonly property var folders: FacadeModel.folders(state.folders)
  readonly property var pendingFolders: state.pendingFolders || ({})
  readonly property var folderStatuses:
    FacadeModel.folderStatuses(state.folders)
  readonly property var syncingFiles: FacadeModel.syncingFiles(activity)
  readonly property int folderCount: Number(counts.folders || 0)
  readonly property int deviceCount: Number(counts.devices || 0)
  readonly property int connectedDeviceCount:
    Number(counts.connectedDevices || 0)
  readonly property int folderProblemCount:
    Number(counts.folderProblems || 0)
  readonly property int syncingFolderCount:
    Number(counts.syncingFolders || 0)
  readonly property string summaryText: summary()

  readonly property string installationState: packageController.state
  readonly property string installationLabel: packageController.label
  readonly property string executablePath:
    String(coreInstallation.executablePath || packageController.executablePath)
  readonly property bool canUseRuntime: coreInstallation.available === true
    || online
  readonly property bool canInstall: packageController.canInstall
  readonly property string packageStatus: packageController.packageStatus
  readonly property string packageError: packageController.packageError
  readonly property bool serviceAvailable: lifecyclePresentation.available
  readonly property bool serviceActive: lifecycle.active === true
  property bool serviceActionRunning: false
  readonly property bool canControlService: lifecyclePresentation.controllable
  property string controlError: ""
  readonly property string configuredServiceState: settings.serviceState
  readonly property int probeIntervalSeconds: settings.probeIntervalSeconds
  readonly property string serviceActiveState:
    String(lifecycle.activeState || "")
  readonly property string serviceUnitFileState:
    String(lifecycle.unitFileState || "")
  readonly property var serviceStateDecision:
    FacadeModel.driftDecision(configuredServiceState, lifecycle)
  readonly property bool serviceStateDrift: settingsReady
    && canControlService && serviceStateDecision.status === "drift"
  readonly property bool serviceStateActionRunning:
    settings.serviceStateActionRunning || serviceActionRunning
  readonly property string serviceStateMessage: serviceStateDrift
    ? serviceStateDecision.message : ""
  readonly property string serviceStatePrimaryLabel: serviceStateDrift
    ? serviceStateDecision.first.label : ""
  readonly property string serviceStateSecondaryLabel: serviceStateDrift
    ? serviceStateDecision.second.label : ""
  readonly property string serviceStateWarning: settingsReady
    && canControlService && serviceStateDecision.status === "unsupported"
    && serviceUnitFileState !== "not-found"
    ? serviceStateDecision.reason : ""

  property bool folderMutationBusy: false
  property string folderMutationId: ""
  property string folderMutationAction: ""
  property string folderMutationError: ""
  property string folderMutationNotice: ""
  property string recentlyLinkedFolderId: ""
  property bool folderPreparationBusy: false
  property string folderPreparationError: ""
  property string folderIdSuggestion: ""

  readonly property string syncActivityDots: currentActivity.detail
    ? [".  ", ".. ", "..."][_activityDotIndex] : ""
  readonly property string syncActivityFolderId:
    String(currentActivity.folderId || "")
  readonly property string syncActivityAction:
    String(currentActivity.action || "")
  readonly property string syncActivityDetail:
    String(currentActivity.detail || "")
  readonly property string syncActivity: syncActivityDetail
    ? "File syncing" + syncActivityDots + " " + syncActivityDetail : ""
  readonly property string iconStyle: settings.iconStyle
  readonly property bool settingsReady: settings.settingsReady
  readonly property bool settingsBusy: settings.busy
  readonly property string settingsError: settings.error
  readonly property string settingsNotice: settings.notice

  property int refreshIntervalSec: 60
  property int _activityDotIndex: 0

  property PersistentProperties identityState: PersistentProperties {
    reloadableId: "syncshell-local-device-identity"
    property string localDeviceId: ""
    property string localDeviceName: ""
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function currentLocalDeviceName() {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].deviceID === localDeviceId) return devices[i].name
    }
    return ""
  }

  function rememberLocalIdentity() {
    if (!localDeviceId) return
    if (identityState.localDeviceId !== localDeviceId) {
      identityState.localDeviceId = localDeviceId
      identityState.localDeviceName = ""
    }
    var name = currentLocalDeviceName()
    if (name) identityState.localDeviceName = name
  }

  function summary() {
    if (installationState === "missing") return "Syncthing is not installed"
    if (installationState === "incomplete") return "Installation needs cleanup"
    if (serviceAvailable && !serviceActive) return "Syncing stopped"
    if (phase === "core-starting") return "Starting Syncshell"
    if (phase === "discovering") return "Finding Syncthing"
    if (phase === "loading") return "Reading status"
    if (phase === "error" || phase === "core-unavailable"
        || phase === "core-incompatible") return "Syncthing unavailable"
    if (folderProblemCount > 0) return folderProblemCount + " folder problem"
      + (folderProblemCount === 1 ? "" : "s")
    if (syncingFolderCount > 0) return syncingFolderCount + " folder"
      + (syncingFolderCount === 1 ? "" : "s") + " syncing"
    return "Up to date"
  }

  function setRefreshInterval(seconds) {
    var value = parseInt(String(seconds), 10)
    if (!isFinite(value)) value = 60
    refreshIntervalSec = Math.max(60, Math.min(3600, value))
  }

  function setLegacyThemedIcon(enabled) {
    settings.setLegacyThemedIcon(enabled)
  }

  function refresh() {
    packageController.updateStatus()
    if (!core.protocolReady || refreshing) return
    refreshing = true
    if (!core.refresh(function(ok, revision, data, error) {
      root.refreshing = false
      if (!ok) root.controlError = actionError(error, "Could not refresh")
    })) refreshing = false
  }

  function configureCore() {
    if (!core.protocolReady || !settingsReady) return
    core.configure({
      probeIntervalSeconds: probeIntervalSeconds,
      desiredServiceState: configuredServiceState
    })
  }

  function actionError(error, fallback) {
    return String(error && error.message || fallback || "Action failed")
  }

  function runFolderAction(action, contractAction, folderId, args, notice) {
    if (!online || folderMutationBusy) {
      folderMutationError = online
        ? "Another folder operation is already running"
        : "Syncthing must be online to manage folders"
      return false
    }
    folderMutationBusy = true
    folderMutationAction = contractAction
    folderMutationId = String(folderId || "")
    folderMutationError = ""
    folderMutationNotice = ""
    var id = core.action(action, args || ({}), function(ok, revision, data, error) {
      root.folderMutationBusy = false
      root.folderMutationAction = ""
      root.folderMutationId = ""
      if (!ok) {
        root.folderMutationError = root.actionError(error,
          "Could not complete the folder operation")
        return
      }
      if (contractAction === "link") {
        root.recentlyLinkedFolderId = String(folderId || "")
        linkedTimer.restart()
      }
      root.folderMutationNotice = String(notice || "")
      if (root.folderMutationNotice) {
        noticeTimer.restart()
        Quickshell.execDetached([
          "omarchy-notification-send", "Syncthing", root.folderMutationNotice
        ])
      }
    })
    if (id) return true
    folderMutationBusy = false
    folderMutationAction = ""
    folderMutationId = ""
    folderMutationError = "Native core is not ready"
    return false
  }

  function folderLabel(folderId) {
    for (var i = 0; i < folders.length; i++) {
      if (folders[i].id === folderId) return folders[i].label || folderId
    }
    return folderId
  }

  function setFolderLinked(folderId, linked) {
    var label = folderLabel(folderId)
    return runFolderAction(linked ? "folder.resume" : "folder.pause",
      linked ? "link" : "unlink", folderId, { folderId: folderId }, linked
        ? "Linked " + label + ". Syncthing resumed the folder with its "
          + "existing sharing configuration."
        : "Synchronization for " + label + " paused. The folder ID, device "
          + "associations, and data remain.")
  }

  function rescanFolder(folderId) {
    return runFolderAction("folder.rescan", "rescan", folderId,
      { folderId: folderId }, "Rescan requested for " + folderLabel(folderId))
  }

  function rescanAllFolders() {
    return runFolderAction("folder.rescan-all", "rescan-all", "", {},
      "Rescan complete for all directories")
  }

  function forgetFolder(folderId) {
    return runFolderAction("folder.forget", "forget", folderId,
      { folderId: folderId }, "Removed from Syncthing configuration and the "
        + "plugin view. The directory and its data files were not deleted. "
        + "Re-add Folder ID " + folderId
        + " to rejoin the same remote folder.")
  }

  function addFolder(path, label, folderId, selectedDeviceIds, pendingDeviceId) {
    var shared = selectedDeviceIds || []
    return runFolderAction("folder.add-existing", "add", folderId, {
      folderId: folderId,
      path: path,
      label: label,
      deviceIds: shared,
      pendingDeviceId: pendingDeviceId
    }, shared.length > 0
      ? "Remote devices may have to accept the folder."
      : "Added " + (label || folderId) + " locally. It is linked but not "
        + "shared with another device.")
  }

  function requestFolderIdSuggestion() {
    if (!online || folderPreparationBusy) return
    folderPreparationBusy = true
    folderPreparationError = ""
    folderIdSuggestion = ""
    var id = core.action("folder.suggest-id", {},
      function(ok, revision, data, error) {
        root.folderPreparationBusy = false
        if (ok) root.folderIdSuggestion = String(data && data.folderId || "")
        else root.folderPreparationError = root.actionError(error,
          "Could not generate a folder ID")
      })
    if (!id) {
      folderPreparationBusy = false
      folderPreparationError = "Native core is not ready"
    }
  }

  function clearFolderMutationMessage() {
    noticeTimer.stop()
    folderMutationError = ""
    folderMutationNotice = ""
  }

  function clearFolderMutationNotice() {
    noticeTimer.stop()
    folderMutationNotice = ""
  }

  function runLifecycle(action) {
    if (!canControlService || serviceActionRunning) return false
    serviceActionRunning = true
    controlError = ""
    var id = core.action("lifecycle." + action, {},
      function(ok, revision, data, error) {
        root.serviceActionRunning = false
        if (!ok) root.controlError = root.actionError(error,
          "Could not update the Syncthing service")
      })
    if (id) return true
    serviceActionRunning = false
    controlError = "Native core is not ready"
    return false
  }

  function toggleService() {
    return runLifecycle(serviceActive ? "stop" : "start")
  }

  function chooseServiceStateAction(index) {
    if (!serviceStateDrift || serviceStateActionRunning) return false
    var selected = index === 0
      ? serviceStateDecision.first : serviceStateDecision.second
    return selected.side === "config"
      ? settings.setServiceState(selected.value)
      : runLifecycle(selected.value === "enabled" ? "enable" : "disable")
  }

  function selectTheme(theme, onSuccess, onError) {
    var id = core.action("webui.set-theme", { theme: theme },
      function(ok, revision, data, error) {
        if (ok) onSuccess()
        else onError(error)
      })
    if (!id) onError({ message: "Native core is not ready" })
  }

  function installSyncthing() { packageController.install() }
  function openSettings() { settings.openSettings() }
  function clearSettingsNotice() { settings.clearNotice() }
  function requestSelfRemoval(deletePluginSettings) {
    settings.requestSelfRemoval(deletePluginSettings)
  }

  onLocalDeviceIdChanged: rememberLocalIdentity()
  onDevicesChanged: rememberLocalIdentity()

  property CoreProcess core: CoreProcess {
    pluginRoot: root.pluginRoot
    startupArguments: [
      "--host-id", "omarchy",
      "--probe-interval-seconds", String(root.probeIntervalSeconds),
      "--desired-service-state", root.configuredServiceState,
      "--lifecycle-kind", "systemd-user",
      "--lifecycle-authorized",
      "--lifecycle-unit", "syncthing.service"
    ]
    onProtocolReadyChanged: if (protocolReady) root.configureCore()
  }

  property SettingsController settings: SettingsController {
    runtimeReady: root.online
    currentWebUiTheme: String(root.webUi.theme || "")
    guiAssetsPath: String(root.webUi.guiAssets || "")
    selectTheme: function(theme, onSuccess, onError) {
      root.selectTheme(theme, onSuccess, onError)
    }
  }

  property PackageController packageController: PackageController {
    helperPath: root.pluginRoot
      + "/hosts/omarchy/scripts/syncthing-install.sh"
    probeIntervalSeconds: root.probeIntervalSeconds
  }

  property Connections settingsConnections: Connections {
    target: settings
    function onSettingsReadyChanged() { root.configureCore() }
    function onProbeIntervalSecondsChanged() { root.configureCore() }
    function onServiceStateChanged() { root.configureCore() }
  }

  property Timer refreshTimer: Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  property Timer activityTimer: Timer {
    interval: 500
    repeat: true
    running: root.syncActivityDetail !== ""
    onTriggered: root._activityDotIndex = (root._activityDotIndex + 1) % 3
  }

  property Timer noticeTimer: Timer {
    interval: 10400
    repeat: false
    onTriggered: root.folderMutationNotice = ""
  }

  property Timer linkedTimer: Timer {
    interval: 10000
    repeat: false
    onTriggered: root.recentlyLinkedFolderId = ""
  }
}

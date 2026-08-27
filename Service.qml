import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "models/ServiceStateModel.js" as ServiceStateModel

QtObject {
  id: root

  readonly property string baseUrl: (_useTls ? "https" : "http")
    + "://127.0.0.1:8384"
  readonly property string apiHelperPath: localPath(
    Qt.resolvedUrl("scripts/syncthing-api.sh"))
  readonly property string helperPath: localPath(
    Qt.resolvedUrl("scripts/syncthing-install.sh"))
  property string phase: "discovering"
  property string lastError: ""
  property bool refreshing: false
  property int refreshIntervalSec: 60
  property var connections: ({})
  property var devices: []
  property var folders: []
  property var pendingFolders: ({})
  property var folderStatuses: ({})
  property string localDeviceId: ""
  readonly property var syncingFiles: activityTracker.syncingFiles

  readonly property bool folderMutationBusy: folderController.mutationBusy
  readonly property string folderMutationId: folderController.mutationId
  readonly property string folderMutationAction: folderController.mutationAction
  readonly property string folderMutationError: folderController.mutationError
  readonly property string folderMutationNotice: folderController.mutationNotice
  readonly property string recentlyLinkedFolderId:
    folderController.recentlyLinkedFolderId
  readonly property bool folderPreparationBusy: folderController.preparationBusy
  readonly property string folderPreparationError:
    folderController.preparationError
  readonly property string folderIdSuggestion: folderController.idSuggestion

  readonly property string installationState: installation.state
  readonly property string installationLabel: installation.label
  readonly property string executablePath: installation.executablePath
  readonly property bool serviceAvailable: installation.serviceAvailable
  readonly property string packageStatus: installation.packageStatus
  readonly property string packageError: installation.packageError
  readonly property string controlError: installation.controlError
  readonly property string recoveryWarning: _recoveryActive
    ? (_apiKey ? "Refreshing Syncthing state" : "Trying to find local API key")
      + [".", "..", "..."][_recoveryDotCount] : ""
  readonly property string syncActivityDots: activityTracker.dots
  readonly property string syncActivityFolderId: activityTracker.folderId
  readonly property string syncActivityAction: activityTracker.action
  readonly property string syncActivityDetail: activityTracker.detail
  readonly property string syncActivity: activityTracker.label
  readonly property string iconStyle: settings.iconStyle
  readonly property bool settingsBusy: settings.busy
  readonly property string settingsError: settings.error
  readonly property string settingsNotice: settings.notice
  readonly property bool settingsReady: settings.settingsReady
  readonly property string configuredServiceState: settings.serviceState
  readonly property string serviceActiveState: installation.serviceActiveState
  readonly property string serviceUnitFileState: installation.unitFileState
  readonly property var serviceStateDecision: ServiceStateModel.decision(
    configuredServiceState, serviceUnitFileState, serviceActiveState)
  readonly property bool serviceStateDrift: settingsReady && serviceAvailable
    && serviceStateDecision.status === "drift"
  readonly property bool serviceStateActionRunning:
    settings.serviceStateActionRunning || installation.unitFileActionRunning
  readonly property string serviceStateMessage: serviceStateDrift
    ? serviceStateDecision.message : ""
  readonly property string serviceStatePrimaryLabel: serviceStateDrift
    ? serviceStateDecision.first.label : ""
  readonly property string serviceStateSecondaryLabel: serviceStateDrift
    ? serviceStateDecision.second.label : ""
  readonly property string serviceStateWarning: settingsReady && serviceAvailable
    && serviceStateDecision.status === "unsupported"
    && serviceUnitFileState !== "not-found"
    ? serviceStateDecision.reason : ""

  property string _apiKey: ""
  property bool _useTls: false
  property bool _recoveryActive: false
  property bool _apiKeyFailureLatched: false
  property int _apiKeyAttempts: 0
  property int _recoveryDotCount: 0
  property int _recoveryTicks: 0
  property bool _finishRecoveryAfterRefresh: false
  property int _generation: 0
  property int _pendingRequests: 0
  property bool _connectionRefreshing: false
  property var _requests: []
  property string _keyOutput: ""

  readonly property bool online: phase === "ready"
  readonly property bool serviceActive: installation.serviceActive
  readonly property bool serviceActionRunning: installation.serviceActionRunning
  readonly property bool canUseRuntime: installation.canUseRuntime
  readonly property bool canControlService: installation.canControlService
  readonly property bool canInstall: installation.canInstall
  readonly property int folderCount: folders.length
  readonly property int deviceCount: devices.length
  readonly property int connectedDeviceCount: countConnectedDevices()
  readonly property int folderProblemCount: countFolderProblems()
  readonly property int syncingFolderCount: countSyncingFolders()
  readonly property string summaryText: summary()

  property ActivityTracker activityTracker: ActivityTracker {
    enabled: root._apiKey !== "" && root.canUseRuntime
      && (!root.serviceAvailable || root.serviceActive)
    requestApi: function(name, options, onSuccess, onError) {
      return root.requestApi(name, options, onSuccess, onError)
    }
    onBecameIdle: root.refreshFolderStatuses(false)
    onPendingFoldersUpdated: function(pending) {
      root.pendingFolders = pending || ({})
    }
  }

  property ApiClient apiClient: ApiClient {
    baseUrl: root.baseUrl
    helperPath: root.apiHelperPath
    apiKey: root._apiKey
    useTls: root._useTls
  }

  property InstallationController installation: InstallationController {
    helperPath: root.helperPath
    folderMutationBusy: root.folderMutationBusy
    onRuntimeUnavailable: function(nextPhase) { root.stopApi(nextPhase) }
    onRuntimeAvailable: {
      if (!root._apiKey && !apiKeyProcess.running) root.refreshApi()
    }
    onServiceStarting: {
      root._apiKeyFailureLatched = false
      root.phase = "discovering"
    }
    onServiceStopping: {
      root._apiKeyFailureLatched = false
      root.stopApi("stopped")
    }
    onServiceStarted: root._apiKey = ""
  }

  property FolderController folderController: FolderController {
    apiReady: root._apiKey !== ""
    online: root.online
    localDeviceId: root.localDeviceId
    folders: root.folders
    devices: root.devices
    pendingFolders: root.pendingFolders
    requestApi: function(name, options, onSuccess, onError) {
      return root.requestApi(name, options, onSuccess, onError)
    }
    refresh: function() { root.refreshApi() }
    onAuthenticationRejected: root._apiKey = ""
    onPendingFoldersUpdated: function(pending) {
      root.pendingFolders = pending || ({})
    }
  }

  property SettingsController settings: SettingsController {
    apiReady: root._apiKey !== "" && root.canUseRuntime
      && (!root.serviceAvailable || root.serviceActive)
    requestApi: function(name, options, onSuccess, onError) {
      return root.requestApi(name, options, onSuccess, onError)
    }
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function countConnectedDevices() {
    var count = 0
    var values = connections && connections.connections
      ? connections.connections : {}
    for (var i = 0; i < devices.length; i++) {
      var id = String((devices[i] || {}).deviceID || "")
      if (id && id === localDeviceId) count++
      else if (id && values[id] && values[id].connected === true) count++
    }
    return count
  }

  function countFolderProblems() {
    var count = 0
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      var status = folderStatuses[ids[i]] || {}
      if (status.state === "error" || status.error
          || Number(status.errors || 0) > 0
          || Number(status.pullErrors || 0) > 0) count++
    }
    return count
  }

  function countSyncingFolders() {
    var count = 0
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      if (Number((folderStatuses[ids[i]] || {}).needTotalItems || 0) > 0) {
        count++
      }
    }
    return count
  }

  function summary() {
    if (installationState === "missing") return "Syncthing is not installed"
    if (installationState === "incomplete") {
      return "Installation needs cleanup"
    }
    if (serviceAvailable && !serviceActive) return "Syncing stopped"
    if (phase === "discovering") return "Finding Syncthing"
    if (phase === "loading") return "Reading status"
    if (phase === "error") return "Syncthing unavailable"
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

  function openSettings() {
    settings.openSettings()
  }

  function clearSettingsNotice() {
    settings.clearNotice()
  }

  function chooseServiceStateAction(index) {
    if (!serviceStateDrift || serviceStateActionRunning) return false
    var action = index === 0
      ? serviceStateDecision.first : serviceStateDecision.second
    if (action.side === "config") return settings.setServiceState(action.value)
    if (action.side === "system") {
      return installation.setUnitFileState(action.value)
    }
    return false
  }

  function requestSelfRemoval(deletePluginSettings) {
    settings.requestSelfRemoval(deletePluginSettings)
  }

  function refresh() {
    _apiKeyFailureLatched = false
    if (phase === "error") lastError = ""
    installation.updateStatus()
    refreshApi()
  }

  function refreshApi() {
    if (installationState === "checking") return
    if (!canUseRuntime) {
      stopApi(installationState)
      return
    }
    if (serviceAvailable && !serviceActive) {
      stopApi("stopped")
      return
    }
    if (!_apiKey) {
      discoverApiKey()
      return
    }

    _generation++
    abortRequests()
    phase = "loading"
    lastError = ""

    fetch("getSystemStatus", {}, function(data) {
      root.localDeviceId = String((data || {}).myID || "")
    })
    fetch("getConnections", {}, function(data) {
      root.connections = data || ({})
    })
    fetch("getDevices", {}, function(data) {
      root.devices = data instanceof Array ? data : []
    })
    fetch("getPendingFolders", {}, function(data) {
      root.pendingFolders = data || ({})
    })
    fetch("getFolders", {}, function(data) {
      root.folders = data instanceof Array ? data : []
      root.folderStatuses = ({})
      for (var i = 0; i < root.folders.length; i++) {
        root.fetchFolder(root.folders[i].id)
      }
    })
  }

  function stopApi(nextPhase) {
    folderController.stop(folderMutationBusy
      ? "Folder operation stopped because Syncthing became unavailable" : "")
    _generation++
    abortRequests()
    stopRecovery()
    _apiKeyFailureLatched = false
    _apiKey = ""
    connections = ({})
    devices = []
    folders = []
    pendingFolders = ({})
    folderStatuses = ({})
    localDeviceId = ""
    activityTracker.stop()
    phase = nextPhase
    lastError = ""
  }

  function fetchFolder(folderId, showProgress) {
    fetch("getFolderStatus", { query: { folder: folderId } }, function(data) {
      root.setFolderStatus(folderId, data || ({}))
    }, function(error) {
      root.setFolderStatus(folderId, {
        state: "error",
        error: error.message
      })
    }, showProgress)
  }

  function refreshFolderStatuses(showProgress) {
    if (!_apiKey || !canUseRuntime
        || (serviceAvailable && !serviceActive)) return
    for (var i = 0; i < folders.length; i++) {
      fetchFolder(folders[i].id, showProgress)
    }
  }

  function setFolderStatus(folderId, status) {
    var next = ({})
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      next[ids[i]] = folderStatuses[ids[i]]
    }
    next[String(folderId)] = status
    folderStatuses = next
  }

  function clearFolderMutationMessage() {
    folderController.clearMessage()
  }

  function clearFolderMutationNotice() {
    folderController.clearNotice()
  }

  function requestFolderIdSuggestion() {
    folderController.requestIdSuggestion()
  }

  function setFolderLinked(folderId, linked) {
    return folderController.setLinked(folderId, linked)
  }

  function forgetFolder(folderId) {
    return folderController.forget(folderId)
  }

  function addFolder(path, label, folderId, selectedDeviceIds, pendingDeviceId) {
    return folderController.add(
      path, label, folderId, selectedDeviceIds, pendingDeviceId)
  }

  function fetch(name, options, onSuccess, onError, showProgress) {
    var generation = _generation
    var visible = showProgress !== false
    if (visible) {
      _pendingRequests++
      refreshing = true
    }
    var xhr = requestApi(name, options, function(data) {
      if (generation !== root._generation) return
      if (onSuccess) onSuccess(data)
      root.finishRequest(generation, visible)
    }, function(error) {
      if (generation !== root._generation) return
      if (onError) onError(error)
      else root.fail(error)
      root.finishRequest(generation, visible)
    })
    var next = _requests.slice()
    next.push(xhr)
    _requests = next
  }

  function requestApi(name, options, onSuccess, onError) {
    return apiClient.request(name, options, onSuccess, onError)
  }

  function finishRequest(generation, visible) {
    if (generation !== _generation) return
    if (visible) {
      _pendingRequests = Math.max(0, _pendingRequests - 1)
      refreshing = _pendingRequests > 0
    }
    if (!refreshing && phase === "loading") phase = "ready"
    if (!refreshing && _finishRecoveryAfterRefresh && phase === "ready") {
      stopRecovery()
    }
  }

  function fail(error) {
    if (error && error.status === 403) _apiKey = ""
    stopRecovery()
    phase = "error"
    lastError = error ? error.message : "Connection failed"
  }

  function abortRequests() {
    for (var i = 0; i < _requests.length; i++) {
      try {
        _requests[i].abort()
      } catch (error) {
      }
    }
    _requests = []
    _pendingRequests = 0
    _connectionRefreshing = false
    refreshing = false
  }

  function discoverApiKey() {
    if (apiKeyProcess.running || !executablePath || _apiKeyFailureLatched) {
      return
    }
    apiKeyRetryTimer.stop()
    if (!_recoveryActive) {
      _recoveryActive = true
      _apiKeyAttempts = 0
      _recoveryDotCount = 0
      _recoveryTicks = 0
      _finishRecoveryAfterRefresh = false
    }
    _apiKeyAttempts++
    _generation++
    abortRequests()
    phase = "discovering"
    lastError = ""
    _keyOutput = ""
    apiKeyProcess.command = [
      executablePath,
      "cli",
      "config",
      "gui",
      "dump-json"
    ]
    apiKeyProcess.running = true
  }

  function stopRecovery() {
    _recoveryActive = false
    _apiKeyAttempts = 0
    _recoveryDotCount = 0
    _recoveryTicks = 0
    _finishRecoveryAfterRefresh = false
    apiKeyRetryTimer.stop()
  }

  function failApiKeyRecovery() {
    stopRecovery()
    _apiKeyFailureLatched = true
    phase = "error"
    lastError = "Could not discover the local API key"
  }

  function installSyncthing() {
    installation.install()
  }

  function toggleService() {
    installation.toggleService()
  }

  function refreshConnections() {
    if (!_apiKey || !canUseRuntime || refreshing || _connectionRefreshing
        || (serviceAvailable && !serviceActive)) return
    _connectionRefreshing = true
    fetch("getConnections", {}, function(data) {
      root.connections = data || ({})
      root._connectionRefreshing = false
    }, function(error) {
      root._connectionRefreshing = false
      root.fail(error)
    }, false)
  }

  property Timer refreshTimer: Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refreshApi()
  }

  property Timer recoveryDotTimer: Timer {
    interval: 500
    repeat: true
    running: root._recoveryActive
    onTriggered: root._recoveryDotCount = (root._recoveryDotCount + 1) % 3
  }

  property Timer apiKeyRetryTimer: Timer {
    interval: 1000
    repeat: false
    onTriggered: root.discoverApiKey()
  }

  property Timer recoveryRefreshTimer: Timer {
    interval: 1000
    repeat: true
    running: root._recoveryActive && root._apiKey !== ""
    onTriggered: {
      if (!root.refreshing) {
        root._recoveryTicks++
        if (root._recoveryTicks >= 10) {
          root._finishRecoveryAfterRefresh = true
          root.refreshApi()
        } else {
          root.refreshConnections()
        }
      }
    }
  }

  property Timer connectionRefreshTimer: Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: if (!root._recoveryActive) root.refreshConnections()
  }

  property Process apiKeyProcess: Process {
    id: apiKeyProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._keyOutput = text
    }
    onExited: function(exitCode) {
      var config = null
      try {
        config = JSON.parse(root._keyOutput)
      } catch (error) {
      }
      var key = config ? String(config.apiKey || "").trim() : ""
      if (exitCode === 0 && key) {
        root._useTls = config.useTLS === true
        root._apiKey = key
        root.apiKeyRetryTimer.stop()
        root._recoveryTicks = 0
        root._finishRecoveryAfterRefresh = false
        root._apiKeyFailureLatched = false
        root.refreshApi()
      } else if (root.canUseRuntime
          && (!root.serviceAvailable || root.serviceActive)) {
        if (root._apiKeyAttempts < 15) root.apiKeyRetryTimer.restart()
        else root.failApiKeyRecovery()
      }
    }
  }

  Component.onDestruction: {
    folderController.stop("")
    _generation++
    abortRequests()
    stopRecovery()
    activityTracker.stop()
    _apiKey = ""
  }
}

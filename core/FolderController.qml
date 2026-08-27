import QtQuick
import Quickshell
import Quickshell.Io
import "../models/FolderModel.js" as FolderModel

QtObject {
  id: root

  property bool apiReady: false
  property bool online: false
  property string localDeviceId: ""
  property string homePath: Quickshell.env("HOME")
  property var folders: []
  property var devices: []
  property var pendingFolders: ({})
  property var requestApi
  property var refresh
  property bool mutationBusy: false
  property string mutationId: ""
  property string mutationAction: ""
  property string mutationError: ""
  property string mutationNotice: ""
  property string recentlyLinkedFolderId: ""
  property bool preparationBusy: false
  property string preparationError: ""
  property string idSuggestion: ""
  property string _pathOutput: ""
  property string _pathErrorOutput: ""
  property var _pendingAdd: null
  property var _mutationRequest: null
  property var _preparationRequest: null
  property int _generation: 0

  signal authenticationRejected
  signal pendingFoldersUpdated(var pending)

  function displayFileName(path) {
    var parts = String(path || "").split(/[\\/]/)
    return parts.length ? parts[parts.length - 1] : ""
  }

  function configuredFolder(folderId) {
    var wanted = String(folderId || "")
    for (var i = 0; i < folders.length; i++) {
      if (String((folders[i] || {}).id || "") === wanted) return folders[i]
    }
    return null
  }

  function configuredDevice(deviceId) {
    var wanted = String(deviceId || "")
    for (var i = 0; i < devices.length; i++) {
      if (String((devices[i] || {}).deviceID || "") === wanted) return devices[i]
    }
    return null
  }

  function resolveFolderPath(value) {
    return FolderModel.resolvePath(value, homePath)
  }

  function errorMessage(error, fallback) {
    return FolderModel.errorMessage(error, fallback)
  }

  function clearMessage() {
    noticeTimer.stop()
    mutationError = ""
    mutationNotice = ""
  }

  function clearNotice() {
    noticeTimer.stop()
    mutationNotice = ""
  }

  function notifyResult(message) {
    if (!message) return
    Quickshell.execDetached([
      "omarchy-notification-send", "Syncthing", String(message)
    ])
  }

  function requestIdSuggestion() {
    if (preparationBusy || !apiReady || !online) return
    preparationBusy = true
    preparationError = ""
    idSuggestion = ""
    try {
      _preparationRequest = requestApi("getRandomString", {
        query: { length: 10 }
      }, function(data) {
        root._preparationRequest = null
        root.preparationBusy = false
        var random = String((data || {}).random || "")
        var suggestion = (random.slice(0, 5) + "-" + random.slice(5)).toLowerCase()
        if (random.length !== 10) {
          root.preparationError = "Syncthing did not return a folder ID"
        } else if (root.configuredFolder(suggestion)) {
          root.preparationError = "Generated folder ID already exists; try again"
        } else {
          root.idSuggestion = suggestion
        }
      }, function(error) {
        root._preparationRequest = null
        root.preparationBusy = false
        root.preparationError = root.errorMessage(
          error, "Could not generate a folder ID")
      })
    } catch (error) {
      _preparationRequest = null
      preparationBusy = false
      preparationError = String(error)
    }
  }

  function begin(action, folderId) {
    if (mutationBusy) return false
    if (!apiReady || !online) {
      mutationError = "Syncthing must be online to manage folders"
      return false
    }
    mutationBusy = true
    mutationAction = String(action || "")
    mutationId = String(folderId || "")
    mutationError = ""
    noticeTimer.stop()
    mutationNotice = ""
    _generation++
    return true
  }

  function finish(notice) {
    _mutationRequest = null
    _pendingAdd = null
    mutationBusy = false
    mutationAction = ""
    mutationId = ""
    mutationNotice = String(notice || "")
    if (mutationNotice) noticeTimer.restart()
    else noticeTimer.stop()
    notifyResult(mutationNotice)
    if (refresh) refresh()
  }

  function fail(error, fallback) {
    _mutationRequest = null
    _pendingAdd = null
    pathProcess.running = false
    directoryProcess.running = false
    mutationBusy = false
    mutationAction = ""
    mutationId = ""
    mutationError = errorMessage(error, fallback)
    if (error && error.status === 403) authenticationRejected()
    if (refresh) refresh()
  }

  function cancel(reason) {
    _generation++
    if (_mutationRequest) {
      try {
        _mutationRequest.abort()
      } catch (error) {
      }
    }
    _mutationRequest = null
    pathProcess.running = false
    directoryProcess.running = false
    _pendingAdd = null
    mutationBusy = false
    mutationAction = ""
    mutationId = ""
    if (reason) mutationError = String(reason)
  }

  function requestMutation(name, options, onSuccess, fallback) {
    var generation = _generation
    try {
      _mutationRequest = requestApi(name, options, function(data, xhr) {
        if (generation !== root._generation || !root.mutationBusy) return
        root._mutationRequest = null
        onSuccess(data, xhr)
      }, function(error) {
        if (generation !== root._generation || !root.mutationBusy) return
        root.fail(error, fallback)
      })
    } catch (error) {
      fail(error, fallback)
    }
  }

  function setLinked(folderId, linked) {
    var folder = configuredFolder(folderId)
    if (!folder) {
      mutationError = "The selected folder is no longer configured"
      return false
    }
    var shouldPause = !linked
    if (!!folder.paused === shouldPause) return true
    if (!begin(linked ? "link" : "unlink", folder.id)) return false
    var label = String(folder.label || folder.id)
    var expectedPath = String(folder.path || "")
    requestMutation("getFolder", {
      path: { id: folder.id }, acceptStatuses: [404]
    }, function(current, xhr) {
      if (xhr.status === 404) {
        root.fail(null, "The folder is no longer configured")
      } else if (!current || String(current.path || "") !== expectedPath) {
        root.fail(null, "The folder configuration changed; refresh and review it")
      } else {
        root.patchLinkedFolder(folder, label, linked, shouldPause)
      }
    }, "Could not verify the folder before changing its linked state")
    return true
  }

  function patchLinkedFolder(folder, label, linked, shouldPause) {
    requestMutation("patchFolder", {
      method: "PATCH", path: { id: folder.id }, json: { paused: shouldPause }
    }, function() {
      if (linked) {
        root.recentlyLinkedFolderId = folder.id
        linkedTimer.restart()
        root.finish("Linked " + label + ". Syncthing resumed the folder with "
          + "its existing sharing configuration.")
      } else {
        root.finish("Synchronization for " + label + " paused. The folder ID, "
          + "device associations, and data remain.")
      }
    }, linked ? "Could not link the folder" : "Could not unlink the folder")
  }

  function rescan(folderId) {
    var folder = configuredFolder(folderId)
    if (!folder) {
      mutationError = "The selected folder is no longer configured"
      return false
    }
    if (folder.paused) {
      mutationError = "Link the folder before rescanning it"
      return false
    }
    if (!begin("rescan", folder.id)) return false
    requestMutation("scanFolder", {
      method: "POST", query: { folder: folder.id }
    }, function() {
      root.finish("Rescan requested for " + String(folder.label || folder.id))
    }, "Could not rescan the folder")
    return true
  }

  function rescanAll() {
    if (folders.length === 0) {
      mutationError = "No directories are configured"
      return false
    }
    if (!begin("rescan-all", "")) return false
    requestMutation("scanFolder", {
      method: "POST"
    }, function() {
      root.finish("Rescan complete for all directories")
    }, "Could not rescan all directories")
    return true
  }

  function forget(folderId) {
    var folder = configuredFolder(folderId)
    if (!folder) {
      mutationError = "The selected folder is no longer configured"
      return false
    }
    if (!folder.paused) {
      mutationError = "Unlink the folder before forgetting it"
      return false
    }
    if (!begin("forget", folder.id)) return false
    verifyFolderBeforeForget(folder)
    return true
  }

  function verifyFolderBeforeForget(folder) {
    requestMutation("getFolder", {
      path: { id: folder.id }, acceptStatuses: [404]
    }, function(current, xhr) {
      if (xhr.status === 404) {
        root.fail(null, "The folder is no longer configured")
      } else if (!current || current.paused !== true) {
        root.fail(null, "The folder is no longer unlinked; refresh and try again")
      } else if (String(current.path || "") !== String(folder.path || "")) {
        root.fail(null, "The folder configuration changed; refresh and review it")
      } else {
        root.deleteFolder(folder)
      }
    }, "Could not verify the folder before forgetting it")
  }

  function deleteFolder(folder) {
    var usesDefaultMarker = String(folder.markerName || ".stfolder") === ".stfolder"
    requestMutation("deleteFolder", {
      method: "DELETE", path: { id: String(folder.id) }
    }, function() {
      root.finish("Removed from Syncthing configuration and the plugin view. "
        + "The directory and its data files were not deleted. "
        + (usesDefaultMarker ? "Syncthing also attempted to remove its internal "
          + ".stfolder marker. " : "") + "Re-add Folder ID " + folder.id
        + " to rejoin the same remote folder.")
    }, "Could not forget the folder")
  }

  function validateAddInput(id, rawPath, requestedPath) {
    return FolderModel.validateAddInput(
      id, rawPath, requestedPath, configuredFolder(id) !== null)
  }

  function selectedDevices(folderId, values) {
    var selected = []
    var seen = ({})
    for (var i = 0; i < values.length; i++) {
      var deviceId = String(values[i] || "")
      if (!deviceId || deviceId === localDeviceId || seen[deviceId]) continue
      var device = configuredDevice(deviceId)
      if (!device) return { error: "A selected device is no longer configured" }
      if (device.untrusted === true) {
        return { error: "Encrypted sharing with untrusted devices must be "
          + "configured in the Syncthing Web UI" }
      }
      var offer = (((pendingFolders[folderId] || {}).offeredBy || ({}))[deviceId]
        || ({}))
      if (offer.receiveEncrypted === true || offer.remoteEncrypted === true) {
        return { error: "Encrypted folder offers must be accepted in the "
          + "Syncthing Web UI" }
      }
      seen[deviceId] = true
      selected.push(deviceId)
    }
    return { ids: selected }
  }

  function add(path, label, folderId, selectedDeviceIds, pendingDeviceId) {
    var id = String(folderId || "")
    var rawPath = String(path || "")
    var requestedPath = resolveFolderPath(rawPath)
    var validationError = validateAddInput(id, rawPath, requestedPath)
    if (validationError) {
      mutationError = validationError
      return false
    }
    var selection = selectedDevices(id, selectedDeviceIds || [])
    if (selection.error) {
      mutationError = selection.error
      return false
    }
    if (!begin("add", id)) return false
    prepareAdd(id, label, requestedPath, selection.ids, pendingDeviceId)
    return true
  }

  function prepareAdd(id, label, requestedPath, selected, pendingDeviceId) {
    _pendingAdd = {
      id: id,
      label: String(label || "").trim(),
      path: requestedPath,
      selectedDeviceIds: selected,
      pendingDeviceId: String(pendingDeviceId || ""),
      configuredPaths: [],
      configuredFolders: []
    }
    _pathOutput = ""
    _pathErrorOutput = ""
    var command = ["realpath", "--canonicalize-missing", "--", requestedPath]
    for (var i = 0; i < folders.length; i++) {
      var configuredPath = resolveFolderPath(String((folders[i] || {}).path || ""))
      if (configuredPath.indexOf("\n") >= 0
          || configuredPath.indexOf("\r") >= 0) {
        fail(null, "A configured folder path contains unsupported line breaks")
        return
      }
      _pendingAdd.configuredPaths.push(configuredPath)
      _pendingAdd.configuredFolders.push({
        id: String((folders[i] || {}).id || ""),
        path: String((folders[i] || {}).path || "")
      })
      command.push(configuredPath)
    }
    pathProcess.command = command
    pathProcess.running = true
  }

  function buildConfig(defaults, pending) {
    return FolderModel.buildConfig(
      defaults, pending, localDeviceId, displayFileName)
  }

  function postPendingFolder() {
    var pending = _pendingAdd
    if (!pending) {
      fail(null, "The folder operation lost its pending state")
      return
    }
    requestMutation("getDefaultFolder", {}, function(defaults) {
      if (!root.localDeviceId) {
        root.fail(null, "Syncthing did not report the local device")
        return
      }
      var config
      try {
        config = root.buildConfig(defaults, pending)
      } catch (error) {
        root.fail(error, "Could not read Syncthing folder defaults")
        return
      }
      root.verifyUnusedId(pending, config)
    }, "Could not read Syncthing folder defaults")
  }

  function verifyUnusedId(pending, config) {
    requestMutation("getFolder", {
      path: { id: pending.id }, acceptStatuses: [404]
    }, function(existing, xhr) {
      if (xhr.status !== 404) {
        root.fail(null, "Folder ID was configured while the add form was open; "
          + "refresh and choose a different ID")
      } else {
        root.verifyFolderSnapshot(pending, config)
      }
    }, "Could not verify the folder ID before adding it")
  }

  function folderSnapshotMatches(pending, current) {
    return FolderModel.folderSnapshotMatches(pending, current)
  }

  function verifyFolderSnapshot(pending, config) {
    requestMutation("getFolders", {}, function(currentFolders) {
      var current = currentFolders instanceof Array ? currentFolders : []
      if (!root.folderSnapshotMatches(pending, current)) {
        root.fail(null, "Syncthing folders changed while the add form was open; "
          + "refresh and review them")
      } else {
        root.verifySelectedDevices(pending, config)
      }
    }, "Could not verify current Syncthing folders")
  }

  function deviceSnapshotError(pending, current) {
    return FolderModel.deviceSnapshotError(pending, current)
  }

  function verifySelectedDevices(pending, config) {
    requestMutation("getDevices", {}, function(currentDevices) {
      var current = currentDevices instanceof Array ? currentDevices : []
      var error = root.deviceSnapshotError(pending, current)
      if (error) root.fail(null, error)
      else root.verifyPendingOffers(pending, config)
    }, "Could not verify selected devices")
  }

  function offerSnapshotError(pending, currentPending) {
    return FolderModel.offerSnapshotError(pending, currentPending)
  }

  function verifyPendingOffers(pending, config) {
    requestMutation("getPendingFolders", {}, function(currentPending) {
      var current = currentPending || ({})
      root.pendingFoldersUpdated(current)
      var error = root.offerSnapshotError(pending, current)
      if (error) root.fail(null, error)
      else root.postConfig(pending, config)
    }, "Could not verify remote folder offers")
  }

  function postConfig(pending, config) {
    requestMutation("addFolder", { method: "POST", json: config }, function() {
      if (pending.selectedDeviceIds.length > 0) {
        root.finish("Remote devices may have to accept the folder.")
      } else {
        root.finish("Added " + config.label + " locally. It is linked but not "
          + "shared with another device.")
      }
    }, "Could not add the folder")
  }

  function resolvedPathError(lines) {
    return FolderModel.resolvedPathError(lines, _pendingAdd, folders)
  }

  function stop(reason) {
    cancel(reason)
    if (_preparationRequest) {
      try {
        _preparationRequest.abort()
      } catch (error) {
      }
    }
    _preparationRequest = null
    preparationBusy = false
    recentlyLinkedFolderId = ""
    linkedTimer.stop()
  }

  property Timer noticeTimer: Timer {
    interval: 10400
    repeat: false
    onTriggered: root.mutationNotice = ""
  }

  property Timer linkedTimer: Timer {
    interval: 10000
    repeat: false
    onTriggered: root.recentlyLinkedFolderId = ""
  }

  property Process pathProcess: Process {
    id: pathProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._pathOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._pathErrorOutput = text
    }
    onExited: function(exitCode) {
      if (!root.mutationBusy || root.mutationAction !== "add"
          || !root._pendingAdd) return
      if (exitCode !== 0) {
        root.fail({ body: root._pathErrorOutput }, "Could not resolve folder path")
        return
      }
      var lines = String(root._pathOutput || "").split("\n")
      if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
      var error = root.resolvedPathError(lines)
      if (error) {
        root.fail(null, error)
        return
      }
      root._pendingAdd.path = lines[0]
      directoryProcess.command = ["test", "-d", lines[0]]
      directoryProcess.running = true
    }
  }

  property Process directoryProcess: Process {
    id: directoryProcess
    command: []
    onExited: function(exitCode) {
      if (!root.mutationBusy || root.mutationAction !== "add"
          || !root._pendingAdd) return
      if (exitCode !== 0) root.fail(null, "Choose an existing local directory")
      else root.postPendingFolder()
    }
  }

  Component.onDestruction: stop("")
}

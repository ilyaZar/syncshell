package session

import (
	"errors"
	"sort"
	"strings"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
)

func normalizeDevices(
	wire []syncthing.Device,
	connections syncthing.Connections,
	localDeviceID string,
) []Device {
	limit := min(len(wire), maxDevices)
	result := make([]Device, 0, limit)
	for _, device := range wire[:limit] {
		connection := connections.Connections[device.DeviceID]
		result = append(result, Device{ID: boundedIdentifier(device.DeviceID),
			Name:      boundedLabel(device.Name),
			Untrusted: device.Untrusted,
			Connected: device.DeviceID == localDeviceID || connection.Connected})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result
}

func normalizedCounts(devices []Device, folders []Folder) Counts {
	counts := Counts{Folders: len(folders), Devices: len(devices)}
	for _, device := range devices {
		if device.Connected {
			counts.ConnectedDevices++
		}
	}
	for _, folder := range folders {
		if folder.Status.State == "error" || folder.Status.Error != "" ||
			folder.Status.PullErrors > 0 || len(folder.Status.Errors) > 0 {
			counts.FolderProblems++
		}
		if folder.Status.NeedTotalItems > 0 {
			counts.SyncingFolders++
		}
	}
	return counts
}

func normalizeFolder(
	folder syncthing.Folder,
	status syncthing.FolderStatus,
	errorsResponse syncthing.FolderErrors,
) (Folder, int) {
	devices := make([]FolderDevice, 0, min(len(folder.Devices), maxFolderDevices))
	for _, device := range folder.Devices[:min(len(folder.Devices), maxFolderDevices)] {
		devices = append(devices, FolderDevice{ID: boundedIdentifier(device.DeviceID)})
	}
	sort.Slice(devices, func(i, j int) bool { return devices[i].ID < devices[j].ID })
	errors := make([]FolderError, 0, min(len(errorsResponse.Errors), maxFolderErrors))
	for _, folderError := range errorsResponse.Errors[:min(len(errorsResponse.Errors), maxFolderErrors)] {
		errors = append(errors, FolderError{Path: boundedLabel(folderError.Path),
			Error: boundedError(folderError.Error)})
	}
	return Folder{
		ID: boundedIdentifier(folder.ID), Label: boundedLabel(folder.Label),
		Path: boundedPath(folder.Path), Paused: folder.Paused,
		MarkerName: boundedIdentifier(folder.MarkerName), Devices: devices,
		Status: FolderStatus{State: boundedLabel(status.State), Error: boundedError(status.Error),
			PullErrors: status.PullErrors, NeedTotalItems: status.NeedTotalItems,
			NeedBytes: status.NeedBytes, GlobalFiles: status.GlobalFiles,
			GlobalBytes: status.GlobalBytes, Errors: errors},
	}, max(0, len(errorsResponse.Errors)-maxFolderErrors)
}

func normalizePendingFolders(pending syncthing.PendingFolders) map[string]PendingFolder {
	result := make(map[string]PendingFolder, min(len(pending), maxPendingFolders))
	folderIDs := sortedPendingFolderIDs(pending)
	for _, folderID := range folderIDs[:min(len(folderIDs), maxPendingFolders)] {
		folder := pending[folderID]
		offers := make(map[string]FolderOffer, min(len(folder.OfferedBy), maxPendingOffers))
		deviceIDs := make([]string, 0, len(folder.OfferedBy))
		for deviceID := range folder.OfferedBy {
			deviceIDs = append(deviceIDs, deviceID)
		}
		sort.Strings(deviceIDs)
		for _, deviceID := range deviceIDs[:min(len(deviceIDs), maxPendingOffers)] {
			offer := folder.OfferedBy[deviceID]
			offers[boundedIdentifier(deviceID)] = FolderOffer{Label: boundedLabel(offer.Label),
				ReceiveEncrypted: offer.ReceiveEncrypted, RemoteEncrypted: offer.RemoteEncrypted}
		}
		result[boundedIdentifier(folderID)] = PendingFolder{OfferedBy: offers}
	}
	return result
}

func collectionTruncation(
	devices []syncthing.Device,
	folders []syncthing.Folder,
	pending syncthing.PendingFolders,
) Truncation {
	truncation := Truncation{
		Devices:        max(0, len(devices)-maxDevices),
		Folders:        max(0, len(folders)-maxFolders),
		PendingFolders: max(0, len(pending)-maxPendingFolders),
	}
	for _, folder := range folders[:min(len(folders), maxFolders)] {
		truncation.FolderDevices += max(0, len(folder.Devices)-maxFolderDevices)
	}
	folderIDs := sortedPendingFolderIDs(pending)
	for _, folderID := range folderIDs[:min(len(folderIDs), maxPendingFolders)] {
		truncation.PendingOffers += max(0,
			len(pending[folderID].OfferedBy)-maxPendingOffers)
	}
	return truncation
}

func sortedPendingFolderIDs(pending syncthing.PendingFolders) []string {
	result := make([]string, 0, len(pending))
	for folderID := range pending {
		result = append(result, folderID)
	}
	sort.Strings(result)
	return result
}

func webURL(endpoint string) string {
	if strings.HasPrefix(endpoint, "http://") || strings.HasPrefix(endpoint, "https://") {
		return endpoint
	}
	return ""
}

func publicError(err error) *Error {
	var target *syncthing.Error
	if errors.As(err, &target) {
		return &Error{Code: string(target.Code), Message: boundedError(target.Error())}
	}
	return &Error{Code: "internal", Message: "Syncshell core request failed"}
}

func rejected(code, message string) ActionResult {
	return ActionResult{Error: &Error{Code: code, Message: message}}
}

func boundedIdentifier(value string) string { return boundedTo(value, maxIdentifier) }

func boundedLabel(value string) string { return boundedTo(value, maxLabel) }

func boundedError(value string) string { return boundedTo(value, maxErrorText) }

func boundedPath(value string) string { return boundedTo(value, maxPublicString) }

func boundedTo(value string, maximum int) string {
	value = strings.TrimSpace(value)
	if len(value) <= maximum {
		return value
	}
	return value[:maximum]
}

func clonePublished(source PublishedSnapshot) PublishedSnapshot {
	copy := source
	if source.State.Connection.Error != nil {
		errorCopy := *source.State.Connection.Error
		copy.State.Connection.Error = &errorCopy
	}
	copy.State.Devices = append([]Device(nil), source.State.Devices...)
	copy.State.Folders = append([]Folder(nil), source.State.Folders...)
	for index := range copy.State.Folders {
		copy.State.Folders[index].Devices = append([]FolderDevice(nil), source.State.Folders[index].Devices...)
		copy.State.Folders[index].Status.Errors = append([]FolderError(nil),
			source.State.Folders[index].Status.Errors...)
	}
	copy.State.PendingFolders = make(map[string]PendingFolder, len(source.State.PendingFolders))
	for folderID, folder := range source.State.PendingFolders {
		offers := make(map[string]FolderOffer, len(folder.OfferedBy))
		for deviceID, offer := range folder.OfferedBy {
			offers[deviceID] = offer
		}
		copy.State.PendingFolders[folderID] = PendingFolder{OfferedBy: offers}
	}
	copy.State.Activity.Files = append([]Activity(nil), source.State.Activity.Files...)
	if source.State.Activity.Current != nil {
		current := *source.State.Activity.Current
		copy.State.Activity.Current = &current
	}
	if source.State.Mutation.Error != nil {
		errorCopy := *source.State.Mutation.Error
		copy.State.Mutation.Error = &errorCopy
	}
	copy.State.Capabilities = append([]string(nil), source.State.Capabilities...)
	return copy
}

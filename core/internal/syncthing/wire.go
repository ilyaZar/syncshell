package syncthing

import "encoding/json"

// SystemStatus is the narrow identity response used by the session.
type SystemStatus struct {
	MyID string `json:"myID"`
}

// SystemVersion is the narrow version response used by the session.
type SystemVersion struct {
	Version string `json:"version"`
}

// Device is the configured-device wire shape required by phase 02.
type Device struct {
	DeviceID  string `json:"deviceID"`
	Name      string `json:"name"`
	Untrusted bool   `json:"untrusted"`
}

// FolderDevice is a folder-sharing relationship.
type FolderDevice struct {
	DeviceID string `json:"deviceID"`
}

// Folder is the configured-folder wire shape required by phase 02.
type Folder struct {
	ID         string         `json:"id"`
	Label      string         `json:"label"`
	Path       string         `json:"path"`
	Paused     bool           `json:"paused"`
	MarkerName string         `json:"markerName"`
	Devices    []FolderDevice `json:"devices"`
}

// FolderStatus is the bounded database status used by the session.
type FolderStatus struct {
	State          string `json:"state"`
	Error          string `json:"error"`
	PullErrors     int    `json:"pullErrors"`
	NeedTotalItems int    `json:"needTotalItems"`
	NeedBytes      int64  `json:"needBytes"`
	GlobalFiles    int    `json:"globalFiles"`
	GlobalBytes    int64  `json:"globalBytes"`
}

// Connections is the configured connection response.
type Connections struct {
	Connections map[string]Connection `json:"connections"`
}

// Connection contains only the fields needed for aggregate state.
type Connection struct {
	Connected bool `json:"connected"`
}

// PendingFolders maps offered folder IDs to their offering devices.
type PendingFolders map[string]PendingFolder

// PendingFolder is one unaccepted folder offer.
type PendingFolder struct {
	OfferedBy map[string]FolderOffer `json:"offeredBy"`
}

// FolderOffer contains the safety-relevant pending-offer fields.
type FolderOffer struct {
	Label            string `json:"label"`
	ReceiveEncrypted bool   `json:"receiveEncrypted"`
	RemoteEncrypted  bool   `json:"remoteEncrypted"`
}

// GUIConfig contains the host-neutral Syncthing GUI state.
type GUIConfig struct {
	Theme string `json:"theme"`
}

// SystemPaths contains only paths required by current host workflows.
type SystemPaths struct {
	GUIAssets string `json:"guiAssets"`
}

// FolderErrors is the current bounded folder error response.
type FolderErrors struct {
	Errors []FolderError `json:"errors"`
}

// FolderError is one current scan or pull error.
type FolderError struct {
	Path  string `json:"path"`
	Error string `json:"error"`
}

// RandomString is a strong server-generated identifier response.
type RandomString struct {
	Random string `json:"random"`
}

// FileInfo is the current local file information used for activity.
type FileInfo struct {
	Local  *FileEntry `json:"local"`
	Global *FileEntry `json:"global"`
}

// FileEntry is the narrow file state required for activity classification.
type FileEntry struct {
	Name    string `json:"name"`
	Type    any    `json:"type"`
	Deleted bool   `json:"deleted"`
}

// Event is the bounded Event API wire envelope.
type Event struct {
	ID   int64           `json:"id"`
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

// FolderConfig preserves the server's current default folder fields.
type FolderConfig map[string]any

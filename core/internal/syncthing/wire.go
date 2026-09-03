package syncthing

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

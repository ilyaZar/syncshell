// Package session owns one selected Syncthing instance and its public state.
package session

import "github.com/omarchy-QOL/syncshell/core/internal/systemduser"

const (
	maxPublicString = 4096
	maxDevices      = 256
	maxFolders      = 256
)

// Error is a sanitized public failure.
type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Connection is authenticated API state for the selected instance.
type Connection struct {
	Phase      string `json:"phase"`
	Endpoint   string `json:"endpoint,omitempty"`
	Healthy    bool   `json:"healthy"`
	Authorized bool   `json:"authorized"`
	Online     bool   `json:"online"`
	Fresh      bool   `json:"fresh"`
	Error      *Error `json:"error,omitempty"`
}

// Identity identifies the authenticated Syncthing instance.
type Identity struct {
	DeviceID string `json:"deviceId,omitempty"`
	Version  string `json:"version,omitempty"`
}

// Device is normalized configured-device state.
type Device struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Untrusted bool   `json:"untrusted"`
	Connected bool   `json:"connected"`
}

// FolderDevice is one normalized folder-sharing relationship.
type FolderDevice struct {
	ID string `json:"id"`
}

// FolderStatus is normalized authoritative folder state.
type FolderStatus struct {
	State          string `json:"state"`
	Error          string `json:"error,omitempty"`
	PullErrors     int    `json:"pullErrors"`
	NeedTotalItems int    `json:"needTotalItems"`
	NeedBytes      int64  `json:"needBytes"`
	GlobalFiles    int    `json:"globalFiles"`
	GlobalBytes    int64  `json:"globalBytes"`
}

// Folder is normalized configured-folder state.
type Folder struct {
	ID         string         `json:"id"`
	Label      string         `json:"label"`
	Path       string         `json:"path"`
	Paused     bool           `json:"paused"`
	MarkerName string         `json:"markerName,omitempty"`
	Devices    []FolderDevice `json:"devices"`
	Status     FolderStatus   `json:"status"`
}

// Snapshot is the complete immutable public state at one revision.
type Snapshot struct {
	HostID       string            `json:"hostId,omitempty"`
	Connection   Connection        `json:"connection"`
	Identity     Identity          `json:"identity"`
	Devices      []Device          `json:"devices"`
	Folders      []Folder          `json:"folders"`
	Lifecycle    systemduser.State `json:"lifecycle"`
	Capabilities []string          `json:"capabilities"`
}

// PublishedSnapshot pairs complete public state with its monotonic revision.
type PublishedSnapshot struct {
	Revision uint64   `json:"revision"`
	State    Snapshot `json:"state"`
}

// OperationalConfig is live, nonsecret host intent.
type OperationalConfig struct {
	ProbeIntervalSeconds *int    `json:"probeIntervalSeconds,omitempty"`
	DesiredServiceState  *string `json:"desiredServiceState,omitempty"`
}

// ActionResult is one correlated domain result.
type ActionResult struct {
	OK       bool   `json:"ok"`
	Revision uint64 `json:"revision,omitempty"`
	Error    *Error `json:"error,omitempty"`
}

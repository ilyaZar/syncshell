// Package session owns one selected Syncthing instance and its public state.
package session

import "github.com/omarchy-QOL/syncshell/core/internal/systemduser"

const (
	maxPublicString   = 4096
	maxIdentifier     = 256
	maxLabel          = 512
	maxErrorText      = 1024
	maxDevices        = 256
	maxFolders        = 128
	maxFolderDevices  = 64
	maxFolderErrors   = 4
	maxPendingFolders = 32
	maxPendingOffers  = 16
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
	State          string        `json:"state"`
	Error          string        `json:"error,omitempty"`
	PullErrors     int           `json:"pullErrors"`
	NeedTotalItems int           `json:"needTotalItems"`
	NeedBytes      int64         `json:"needBytes"`
	GlobalFiles    int           `json:"globalFiles"`
	GlobalBytes    int64         `json:"globalBytes"`
	Errors         []FolderError `json:"errors"`
}

// FolderError is one bounded current scan or pull error.
type FolderError struct {
	Path  string `json:"path"`
	Error string `json:"error"`
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

// FolderOffer is one current unencrypted or encrypted folder offer.
type FolderOffer struct {
	Label            string `json:"label"`
	ReceiveEncrypted bool   `json:"receiveEncrypted"`
	RemoteEncrypted  bool   `json:"remoteEncrypted"`
}

// PendingFolder maps offering device IDs to offer metadata.
type PendingFolder struct {
	OfferedBy map[string]FolderOffer `json:"offeredBy"`
}

// Activity is one bounded current file operation.
type Activity struct {
	FolderID string `json:"folderId"`
	Path     string `json:"path"`
	Action   string `json:"action"`
	Detail   string `json:"detail"`
}

// ActivityState is the session-owned bounded activity rotation.
type ActivityState struct {
	Files   []Activity `json:"files"`
	Current *Activity  `json:"current,omitempty"`
}

// WebUI is host-neutral Syncthing GUI state.
type WebUI struct {
	URL       string `json:"url,omitempty"`
	Theme     string `json:"theme,omitempty"`
	GUIAssets string `json:"guiAssets,omitempty"`
}

// Installation contains host-neutral executable facts only.
type Installation struct {
	ExecutablePath string `json:"executablePath,omitempty"`
	Available      bool   `json:"available"`
}

// Mutation is the single serialized action state.
type Mutation struct {
	Busy       bool   `json:"busy"`
	ID         string `json:"id,omitempty"`
	Action     string `json:"action,omitempty"`
	Error      *Error `json:"error,omitempty"`
	Suggestion string `json:"suggestion,omitempty"`
}

// Counts contains normalized aggregate state used by rich hosts.
type Counts struct {
	Folders          int `json:"folders"`
	Devices          int `json:"devices"`
	ConnectedDevices int `json:"connectedDevices"`
	FolderProblems   int `json:"folderProblems"`
	SyncingFolders   int `json:"syncingFolders"`
}

// Truncation reports collection entries omitted to preserve protocol bounds.
type Truncation struct {
	Devices        int `json:"devices,omitempty"`
	Folders        int `json:"folders,omitempty"`
	FolderDevices  int `json:"folderDevices,omitempty"`
	FolderErrors   int `json:"folderErrors,omitempty"`
	PendingFolders int `json:"pendingFolders,omitempty"`
	PendingOffers  int `json:"pendingOffers,omitempty"`
}

// Snapshot is the complete immutable public state at one revision.
type Snapshot struct {
	HostID         string                   `json:"hostId,omitempty"`
	Connection     Connection               `json:"connection"`
	Identity       Identity                 `json:"identity"`
	Devices        []Device                 `json:"devices"`
	Folders        []Folder                 `json:"folders"`
	PendingFolders map[string]PendingFolder `json:"pendingFolders"`
	Activity       ActivityState            `json:"activity"`
	WebUI          WebUI                    `json:"webUi"`
	Installation   Installation             `json:"installation"`
	Mutation       Mutation                 `json:"mutation"`
	Counts         Counts                   `json:"counts"`
	Truncation     Truncation               `json:"truncation"`
	Lifecycle      systemduser.State        `json:"lifecycle"`
	Capabilities   []string                 `json:"capabilities"`
}

// PublishedSnapshot pairs complete public state with its monotonic revision.
type PublishedSnapshot struct {
	Revision uint64   `json:"revision"`
	State    Snapshot `json:"state"`
}

// OperationalConfig is live, nonsecret host intent.
type OperationalConfig struct {
	ProbeIntervalSeconds   *int    `json:"probeIntervalSeconds,omitempty"`
	RefreshIntervalSeconds *int    `json:"refreshIntervalSeconds,omitempty"`
	DesiredServiceState    *string `json:"desiredServiceState,omitempty"`
}

// ActionResult is one correlated domain result.
type ActionResult struct {
	OK       bool   `json:"ok"`
	Revision uint64 `json:"revision,omitempty"`
	Data     any    `json:"data,omitempty"`
	Error    *Error `json:"error,omitempty"`
}

// ActionArguments is the single protocol-to-session action input shape.
type ActionArguments struct {
	FolderID        string   `json:"folderId,omitempty"`
	Path            string   `json:"path,omitempty"`
	Label           string   `json:"label,omitempty"`
	DeviceIDs       []string `json:"deviceIds,omitempty"`
	PendingDeviceID string   `json:"pendingDeviceId,omitempty"`
	Theme           string   `json:"theme,omitempty"`
}

package session

import (
	"context"
	"reflect"
	"sort"
	"sync"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
	"github.com/omarchy-QOL/syncshell/core/internal/systemduser"
)

// Config constructs one authoritative session.
type Config struct {
	HostID              string
	Discovery           syncthing.DiscoveryOptions
	Lifecycle           systemduser.Binding
	SystemdCommand      string
	ProbeInterval       time.Duration
	DesiredServiceState string
}

type hydratedState struct {
	identity       Identity
	devices        []Device
	folders        []Folder
	pendingFolders map[string]PendingFolder
	webUI          WebUI
	truncation     Truncation
}

// Session owns refresh, public state, lifecycle classification, and mutation
// serialization for one selected instance.
type Session struct {
	hostID     string
	executable string
	client     *syncthing.Client
	target     syncthing.Target
	binding    systemduser.Binding
	lifecycle  systemduser.Controller

	refreshMu sync.Mutex
	actionMu  sync.Mutex
	stateMu   sync.RWMutex
	current   PublishedSnapshot

	configMu            sync.RWMutex
	probeInterval       time.Duration
	refreshInterval     time.Duration
	desiredServiceState string
	configChanged       chan struct{}

	eventsOnce      sync.Once
	activityMu      sync.Mutex
	activityRecords map[string]activityRecord
	activityIndex   int
	externalLatched bool
}

// New discovers exactly one target and constructs its sole session.
func New(ctx context.Context, config Config) (*Session, error) {
	target, err := syncthing.Discover(ctx, config.Discovery)
	if err != nil {
		return nil, err
	}
	client, err := syncthing.NewClient(target)
	if err != nil {
		return nil, err
	}
	interval := config.ProbeInterval
	if interval <= 0 {
		interval = 15 * time.Second
	}
	desired := config.DesiredServiceState
	if desired == "" {
		desired = "enabled"
	}
	return &Session{
		hostID:              boundedIdentifier(config.HostID),
		executable:          syncthing.FindExecutable(config.Discovery.SyncthingBinary),
		client:              client,
		target:              target,
		binding:             config.Lifecycle,
		lifecycle:           systemduser.Controller{Command: config.SystemdCommand},
		probeInterval:       interval,
		refreshInterval:     60 * time.Second,
		desiredServiceState: desired,
		configChanged:       make(chan struct{}, 1),
		activityRecords:     make(map[string]activityRecord),
	}, nil
}

// Current returns a copy of the latest immutable public state.
func (s *Session) Current() PublishedSnapshot {
	s.stateMu.RLock()
	defer s.stateMu.RUnlock()
	return clonePublished(s.current)
}

// ProbeInterval returns the current validated lifecycle probe interval.
func (s *Session) ProbeInterval() time.Duration {
	s.configMu.RLock()
	defer s.configMu.RUnlock()
	return s.probeInterval
}

// RefreshInterval returns the current authoritative reconciliation interval.
func (s *Session) RefreshInterval() time.Duration {
	s.configMu.RLock()
	defer s.configMu.RUnlock()
	return s.refreshInterval
}

// Refresh rebuilds authoritative state through the one selected client.
func (s *Session) Refresh(ctx context.Context) (PublishedSnapshot, error) {
	s.refreshMu.Lock()
	defer s.refreshMu.Unlock()

	snapshot, refreshErr := s.hydrate(ctx)
	published := s.publish(snapshot)
	return published, refreshErr
}

func (s *Session) hydrate(ctx context.Context) (Snapshot, error) {
	previous := s.Current().State
	snapshot := Snapshot{
		HostID:         s.hostID,
		Connection:     Connection{Phase: "loading", Endpoint: s.client.Endpoint()},
		Identity:       previous.Identity,
		Devices:        previous.Devices,
		Folders:        previous.Folders,
		PendingFolders: previous.PendingFolders,
		Activity:       previous.Activity,
		WebUI:          previous.WebUI,
		Installation: Installation{ExecutablePath: boundedPath(s.executable),
			Available: s.executable != ""},
		Mutation:   previous.Mutation,
		Truncation: previous.Truncation,
		Capabilities: []string{
			"configure", "folder.add-existing", "folder.forget", "folder.pause",
			"folder.rescan", "folder.rescan-all", "folder.resume", "folder.suggest-id",
			"lifecycle.disable", "lifecycle.enable", "lifecycle.start", "lifecycle.stop",
			"refresh", "webui.set-theme",
		},
	}
	if err := s.client.Health(ctx); err != nil {
		snapshot.Connection.Phase = "error"
		snapshot.Connection.Error = publicError(err)
		snapshot.Lifecycle = s.failureLifecycle(ctx)
		return snapshot, err
	}
	snapshot.Connection.Healthy = true

	status, err := s.client.Status(ctx)
	if err != nil {
		snapshot.Connection.Phase = "error"
		snapshot.Connection.Error = publicError(err)
		snapshot.Lifecycle = s.failureLifecycle(ctx)
		snapshot.Lifecycle.Classification = "external"
		snapshot.Lifecycle.TargetMatch = false
		snapshot.Lifecycle.CanControl = false
		snapshot.Lifecycle.CanStart = false
		s.externalLatched = true
		return snapshot, err
	}
	snapshot.Connection.Authorized = true
	if expected := s.target.ExpectedDeviceID; expected != "" && expected != status.MyID {
		err = &syncthing.Error{Code: syncthing.ErrorIdentity, Op: "identity",
			Message: "Syncthing device identity does not match the selected target"}
		snapshot.Connection.Phase = "error"
		snapshot.Connection.Error = publicError(err)
		snapshot.Lifecycle = s.probeLifecycle(ctx, false)
		snapshot.Lifecycle.Classification = "external"
		snapshot.Lifecycle.TargetMatch = false
		snapshot.Lifecycle.CanControl = false
		snapshot.Lifecycle.CanStart = false
		s.externalLatched = true
		return snapshot, err
	}

	hydrated, err := s.loadAuthenticated(ctx, status)
	if err != nil {
		return s.failedHydration(ctx, snapshot, err)
	}
	snapshot.Identity = hydrated.identity
	snapshot.Devices = hydrated.devices
	snapshot.Folders = hydrated.folders
	snapshot.PendingFolders = hydrated.pendingFolders
	snapshot.WebUI = hydrated.webUI
	snapshot.Counts = normalizedCounts(hydrated.devices, hydrated.folders)
	snapshot.Truncation = hydrated.truncation
	snapshot.Connection.Phase = "ready"
	snapshot.Connection.Online = true
	snapshot.Connection.Fresh = true
	snapshot.Connection.Error = nil
	snapshot.Lifecycle = s.probeLifecycle(ctx, true)
	s.externalLatched = snapshot.Lifecycle.Classification == "external"
	return snapshot, nil
}

func (s *Session) loadAuthenticated(
	ctx context.Context,
	status syncthing.SystemStatus,
) (hydratedState, error) {
	version, err := s.client.Version(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	devices, err := s.client.Devices(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	folders, err := s.client.Folders(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	connections, err := s.client.Connections(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	normalizedFolders, omittedFolderErrors, err := s.loadFolders(ctx, folders)
	if err != nil {
		return hydratedState{}, err
	}
	pending, err := s.client.PendingFolders(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	gui, err := s.client.GUIConfig(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	paths, err := s.client.SystemPaths(ctx)
	if err != nil {
		return hydratedState{}, err
	}
	truncation := collectionTruncation(devices, folders, pending)
	truncation.FolderErrors = omittedFolderErrors
	return hydratedState{
		identity: Identity{DeviceID: boundedIdentifier(status.MyID),
			Version: boundedLabel(version.Version)},
		devices:        normalizeDevices(devices, connections, status.MyID),
		folders:        normalizedFolders,
		pendingFolders: normalizePendingFolders(pending),
		webUI: WebUI{URL: webURL(s.client.Endpoint()), Theme: boundedIdentifier(gui.Theme),
			GUIAssets: boundedPath(paths.GUIAssets)},
		truncation: truncation,
	}, nil
}

func (s *Session) loadFolders(
	ctx context.Context,
	folders []syncthing.Folder,
) ([]Folder, int, error) {
	result := make([]Folder, 0, min(len(folders), maxFolders))
	omittedErrors := 0
	for _, folder := range folders[:min(len(folders), maxFolders)] {
		status, err := s.client.FolderStatus(ctx, folder.ID)
		if err != nil {
			return nil, 0, err
		}
		errorsResponse, err := s.client.FolderErrors(ctx, folder.ID)
		if err != nil {
			return nil, 0, err
		}
		normalized, omitted := normalizeFolder(folder, status, errorsResponse)
		result = append(result, normalized)
		omittedErrors += omitted
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result, omittedErrors, nil
}

func (s *Session) failedHydration(ctx context.Context, snapshot Snapshot, err error) (Snapshot, error) {
	snapshot.Connection.Phase = "error"
	snapshot.Connection.Error = publicError(err)
	snapshot.Lifecycle = s.failureLifecycle(ctx)
	return snapshot, err
}

func (s *Session) failureLifecycle(ctx context.Context) systemduser.State {
	state := s.probeLifecycle(ctx, false)
	if s.externalLatched {
		state.Classification = "external"
		state.CanControl = false
		state.CanStart = false
	}
	return state
}

func (s *Session) probeLifecycle(ctx context.Context, apiOnline bool) systemduser.State {
	state := s.lifecycle.Probe(ctx, s.binding, systemduser.Target{
		ConfigPath: s.target.ConfigPath,
		Local:      s.target.Local,
		Automatic:  s.target.Automatic,
	}, apiOnline)
	s.configMu.RLock()
	state.DesiredState = s.desiredServiceState
	s.configMu.RUnlock()
	return state
}

func (s *Session) refreshLifecycle(ctx context.Context) PublishedSnapshot {
	s.refreshMu.Lock()
	defer s.refreshMu.Unlock()

	current := s.Current()
	if current.Revision == 0 {
		return current
	}
	state := s.probeLifecycle(ctx, true)
	if !current.State.Connection.Online {
		state = s.failureLifecycle(ctx)
	}

	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	if desired := s.current.State.Lifecycle.DesiredState; desired != "" {
		state.DesiredState = desired
	}
	if !reflect.DeepEqual(s.current.State.Lifecycle, state) {
		s.current.State.Lifecycle = state
		s.current.Revision++
	}
	return clonePublished(s.current)
}

func (s *Session) publish(snapshot Snapshot) PublishedSnapshot {
	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	if s.current.Revision == 0 || !reflect.DeepEqual(s.current.State, snapshot) {
		s.current.Revision++
		s.current.State = snapshot
	}
	return clonePublished(s.current)
}

// Configure applies validated operational intent in memory only.
func (s *Session) Configure(config OperationalConfig) ActionResult {
	if result := validateOperationalConfig(config); result != nil {
		return *result
	}
	s.configMu.Lock()
	if config.ProbeIntervalSeconds != nil {
		s.probeInterval = time.Duration(*config.ProbeIntervalSeconds) * time.Second
	}
	if config.RefreshIntervalSeconds != nil {
		s.refreshInterval = time.Duration(*config.RefreshIntervalSeconds) * time.Second
	}
	if config.DesiredServiceState != nil {
		s.desiredServiceState = *config.DesiredServiceState
	}
	desired := s.desiredServiceState
	s.configMu.Unlock()
	select {
	case s.configChanged <- struct{}{}:
	default:
	}
	s.publishDesiredState(desired)
	return ActionResult{OK: true, Revision: s.Current().Revision}
}

func validateOperationalConfig(config OperationalConfig) *ActionResult {
	if config.ProbeIntervalSeconds != nil {
		seconds := *config.ProbeIntervalSeconds
		if seconds < 1 || seconds > 3600 {
			result := rejected("invalid_config", "probe interval must be between 1 and 3600 seconds")
			return &result
		}
	}
	if config.RefreshIntervalSeconds != nil {
		seconds := *config.RefreshIntervalSeconds
		if seconds < 60 || seconds > 3600 {
			result := rejected("invalid_config",
				"refresh interval must be between 60 and 3600 seconds")
			return &result
		}
	}
	if config.DesiredServiceState != nil {
		state := *config.DesiredServiceState
		if state != "enabled" && state != "disabled" {
			result := rejected("invalid_config", "desired service state must be enabled or disabled")
			return &result
		}
	}
	return nil
}

func (s *Session) publishDesiredState(desired string) {
	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	if s.current.Revision == 0 || s.current.State.Lifecycle.DesiredState == desired {
		return
	}
	s.current.State.Lifecycle.DesiredState = desired
	s.current.Revision++
}

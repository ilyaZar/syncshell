package session

import (
	"context"
	"errors"
	"reflect"
	"sort"
	"strings"
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
	identity Identity
	devices  []Device
	folders  []Folder
}

// Session owns refresh, public state, lifecycle classification, and mutation
// serialization for one selected instance.
type Session struct {
	hostID    string
	client    *syncthing.Client
	target    syncthing.Target
	binding   systemduser.Binding
	lifecycle systemduser.Controller

	refreshMu sync.Mutex
	actionMu  sync.Mutex
	stateMu   sync.RWMutex
	current   PublishedSnapshot

	configMu            sync.RWMutex
	probeInterval       time.Duration
	desiredServiceState string
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
		hostID:              bounded(config.HostID),
		client:              client,
		target:              target,
		binding:             config.Lifecycle,
		lifecycle:           systemduser.Controller{Command: config.SystemdCommand},
		probeInterval:       interval,
		desiredServiceState: desired,
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
		HostID:       s.hostID,
		Connection:   Connection{Phase: "loading", Endpoint: s.client.Endpoint()},
		Identity:     previous.Identity,
		Devices:      previous.Devices,
		Folders:      previous.Folders,
		Capabilities: []string{"configure", "folder.rescan", "refresh"},
	}
	if err := s.client.Health(ctx); err != nil {
		snapshot.Connection.Phase = "error"
		snapshot.Connection.Error = publicError(err)
		snapshot.Lifecycle = s.probeLifecycle(ctx, false)
		return snapshot, err
	}
	snapshot.Connection.Healthy = true

	status, err := s.client.Status(ctx)
	if err != nil {
		snapshot.Connection.Phase = "error"
		snapshot.Connection.Error = publicError(err)
		snapshot.Lifecycle = s.probeLifecycle(ctx, false)
		snapshot.Lifecycle.Classification = "external"
		snapshot.Lifecycle.TargetMatch = false
		snapshot.Lifecycle.CanControl = false
		snapshot.Lifecycle.CanStart = false
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
		return snapshot, err
	}

	hydrated, err := s.loadAuthenticated(ctx, status)
	if err != nil {
		return s.failedHydration(ctx, snapshot, err)
	}
	snapshot.Identity = hydrated.identity
	snapshot.Devices = hydrated.devices
	snapshot.Folders = hydrated.folders
	snapshot.Connection.Phase = "ready"
	snapshot.Connection.Online = true
	snapshot.Connection.Fresh = true
	snapshot.Connection.Error = nil
	snapshot.Lifecycle = s.probeLifecycle(ctx, true)
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
	normalizedFolders, err := s.loadFolders(ctx, folders)
	if err != nil {
		return hydratedState{}, err
	}
	return hydratedState{
		identity: Identity{DeviceID: bounded(status.MyID), Version: bounded(version.Version)},
		devices:  normalizeDevices(devices, connections),
		folders:  normalizedFolders,
	}, nil
}

func (s *Session) loadFolders(ctx context.Context, folders []syncthing.Folder) ([]Folder, error) {
	result := make([]Folder, 0, min(len(folders), maxFolders))
	for _, folder := range folders[:min(len(folders), maxFolders)] {
		status, err := s.client.FolderStatus(ctx, folder.ID)
		if err != nil {
			return nil, err
		}
		result = append(result, normalizeFolder(folder, status))
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result, nil
}

func (s *Session) failedHydration(ctx context.Context, snapshot Snapshot, err error) (Snapshot, error) {
	snapshot.Connection.Phase = "error"
	snapshot.Connection.Error = publicError(err)
	snapshot.Lifecycle = s.probeLifecycle(ctx, false)
	return snapshot, err
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
	if config.DesiredServiceState != nil {
		s.desiredServiceState = *config.DesiredServiceState
	}
	desired := s.desiredServiceState
	s.configMu.Unlock()
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

// Rescan serializes and validates the phase-02 mutation path.
func (s *Session) Rescan(ctx context.Context, folderID string) ActionResult {
	s.actionMu.Lock()
	defer s.actionMu.Unlock()

	folderID = strings.TrimSpace(folderID)
	current := s.Current()
	if !current.State.Connection.Online {
		return rejected("offline", "Syncthing is not online")
	}
	var selected *Folder
	for index := range current.State.Folders {
		if current.State.Folders[index].ID == folderID {
			selected = &current.State.Folders[index]
			break
		}
	}
	if selected == nil {
		return rejected("folder_missing", "folder is no longer configured")
	}
	if selected.Paused {
		return rejected("folder_paused", "paused folders cannot be rescanned")
	}
	if err := s.client.Rescan(ctx, folderID); err != nil {
		return ActionResult{Error: publicError(err)}
	}
	refreshed, err := s.Refresh(ctx)
	if err != nil {
		return ActionResult{Error: publicError(err), Revision: refreshed.Revision}
	}
	return ActionResult{OK: true, Revision: refreshed.Revision}
}

func normalizeDevices(wire []syncthing.Device, connections syncthing.Connections) []Device {
	limit := min(len(wire), maxDevices)
	result := make([]Device, 0, limit)
	for _, device := range wire[:limit] {
		connection := connections.Connections[device.DeviceID]
		result = append(result, Device{ID: bounded(device.DeviceID), Name: bounded(device.Name),
			Untrusted: device.Untrusted, Connected: connection.Connected})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].ID < result[j].ID })
	return result
}

func normalizeFolder(folder syncthing.Folder, status syncthing.FolderStatus) Folder {
	devices := make([]FolderDevice, 0, min(len(folder.Devices), maxDevices))
	for _, device := range folder.Devices[:min(len(folder.Devices), maxDevices)] {
		devices = append(devices, FolderDevice{ID: bounded(device.DeviceID)})
	}
	return Folder{
		ID: bounded(folder.ID), Label: bounded(folder.Label), Path: bounded(folder.Path),
		Paused: folder.Paused, MarkerName: bounded(folder.MarkerName), Devices: devices,
		Status: FolderStatus{State: bounded(status.State), Error: bounded(status.Error),
			PullErrors: status.PullErrors, NeedTotalItems: status.NeedTotalItems,
			NeedBytes: status.NeedBytes, GlobalFiles: status.GlobalFiles,
			GlobalBytes: status.GlobalBytes},
	}
}

func publicError(err error) *Error {
	var target *syncthing.Error
	if errors.As(err, &target) {
		return &Error{Code: string(target.Code), Message: bounded(target.Error())}
	}
	return &Error{Code: "internal", Message: "Syncshell core request failed"}
}

func rejected(code, message string) ActionResult {
	return ActionResult{Error: &Error{Code: code, Message: message}}
}

func bounded(value string) string {
	value = strings.TrimSpace(value)
	if len(value) <= maxPublicString {
		return value
	}
	return value[:maxPublicString]
}

func clonePublished(source PublishedSnapshot) PublishedSnapshot {
	copy := source
	copy.State.Devices = append([]Device(nil), source.State.Devices...)
	copy.State.Folders = append([]Folder(nil), source.State.Folders...)
	for index := range copy.State.Folders {
		copy.State.Folders[index].Devices = append([]FolderDevice(nil), source.State.Folders[index].Devices...)
	}
	copy.State.Capabilities = append([]string(nil), source.State.Capabilities...)
	return copy
}

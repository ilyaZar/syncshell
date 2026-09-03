package session

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
)

var safeName = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// Act serializes, publishes, validates, and executes one domain action.
func (s *Session) Act(
	ctx context.Context,
	action string,
	arguments ActionArguments,
	requestID string,
	publish func(PublishedSnapshot),
) ActionResult {
	s.actionMu.Lock()
	defer s.actionMu.Unlock()
	s.publishMutation(Mutation{Busy: true, ID: boundedIdentifier(requestID),
		Action: boundedIdentifier(action)}, publish)

	var result ActionResult
	if validation := validateActionArguments(action, arguments); validation != nil {
		return s.finishMutation(action, requestID, *validation, publish)
	}
	switch action {
	case "folder.pause":
		result = s.setFolderPaused(ctx, arguments.FolderID, true)
	case "folder.resume":
		result = s.setFolderPaused(ctx, arguments.FolderID, false)
	case "folder.rescan":
		result = s.rescanFolder(ctx, arguments.FolderID)
	case "folder.rescan-all":
		result = s.rescanAll(ctx)
	case "folder.forget":
		result = s.forgetFolder(ctx, arguments.FolderID)
	case "folder.add-existing":
		result = s.addExistingFolder(ctx, arguments)
	case "folder.suggest-id":
		result = s.suggestFolderID(ctx)
	case "lifecycle.start", "lifecycle.stop", "lifecycle.enable", "lifecycle.disable":
		result = s.lifecycleAction(ctx, strings.TrimPrefix(action, "lifecycle."))
	case "webui.set-theme":
		result = s.setWebUITheme(ctx, arguments.Theme)
	default:
		result = rejected("unsupported_action", "action is not supported")
	}
	return s.finishMutation(action, requestID, result, publish)
}

func validateActionArguments(action string, arguments ActionArguments) *ActionResult {
	folderOnly := arguments.FolderID != "" && arguments.Path == "" &&
		arguments.Label == "" && len(arguments.DeviceIDs) == 0 &&
		arguments.PendingDeviceID == "" && arguments.Theme == ""
	empty := arguments.FolderID == "" && arguments.Path == "" &&
		arguments.Label == "" && len(arguments.DeviceIDs) == 0 &&
		arguments.PendingDeviceID == "" && arguments.Theme == ""
	valid := false
	switch action {
	case "folder.pause", "folder.resume", "folder.rescan", "folder.forget":
		valid = folderOnly
	case "folder.rescan-all", "folder.suggest-id",
		"lifecycle.start", "lifecycle.stop", "lifecycle.enable", "lifecycle.disable":
		valid = empty
	case "folder.add-existing":
		valid = arguments.Theme == ""
	case "webui.set-theme":
		valid = arguments.Theme != "" && arguments.FolderID == "" && arguments.Path == "" &&
			arguments.Label == "" && len(arguments.DeviceIDs) == 0 &&
			arguments.PendingDeviceID == ""
	default:
		valid = empty
	}
	if valid {
		return nil
	}
	result := rejected("invalid_action", "action arguments are invalid")
	return &result
}

func (s *Session) setFolderPaused(ctx context.Context, folderID string, paused bool) ActionResult {
	snapshotFolder, currentFolder, result := s.verifiedFolder(ctx, folderID)
	if result.Error != nil {
		return result
	}
	if snapshotFolder.Paused != currentFolder.Paused {
		return rejected("folder_changed", "folder changed before the action")
	}
	if currentFolder.Paused == paused {
		if paused {
			return rejected("folder_paused", "folder is already paused")
		}
		return rejected("folder_active", "folder is already active")
	}
	if err := s.client.PatchFolder(ctx, folderID, map[string]bool{"paused": paused}); err != nil {
		return s.afterAmbiguousMutation(ctx, err)
	}
	return s.refreshAfterMutation(ctx)
}

func (s *Session) rescanFolder(ctx context.Context, folderID string) ActionResult {
	snapshotFolder, currentFolder, result := s.verifiedFolder(ctx, folderID)
	if result.Error != nil {
		return result
	}
	if snapshotFolder.Paused || currentFolder.Paused {
		return rejected("folder_paused", "paused folders cannot be rescanned")
	}
	if err := s.client.Rescan(ctx, folderID); err != nil {
		return ActionResult{Error: publicError(err)}
	}
	return s.refreshAfterMutation(ctx)
}

func (s *Session) rescanAll(ctx context.Context) ActionResult {
	if result := s.requireOnline(); result != nil {
		return *result
	}
	folders, err := s.client.Folders(ctx)
	if err != nil {
		return ActionResult{Error: publicError(err)}
	}
	if len(folders) == 0 {
		return rejected("folder_missing", "no folders are configured")
	}
	linked := false
	for _, folder := range folders {
		if !folder.Paused {
			linked = true
			break
		}
	}
	if !linked {
		return rejected("folder_paused", "no linked folders are available to rescan")
	}
	if err := s.client.Rescan(ctx, ""); err != nil {
		return ActionResult{Error: publicError(err)}
	}
	return s.refreshAfterMutation(ctx)
}

func (s *Session) forgetFolder(ctx context.Context, folderID string) ActionResult {
	snapshotFolder, currentFolder, result := s.verifiedFolder(ctx, folderID)
	if result.Error != nil {
		return result
	}
	if !snapshotFolder.Paused || !currentFolder.Paused {
		return rejected("folder_active", "folder must be paused before it is forgotten")
	}
	if err := s.client.DeleteFolder(ctx, folderID); err != nil {
		return s.afterAmbiguousMutation(ctx, err)
	}
	return s.refreshAfterMutation(ctx)
}

func (s *Session) addExistingFolder(ctx context.Context, arguments ActionArguments) ActionResult {
	if result := s.requireOnline(); result != nil {
		return *result
	}
	folderID := strings.TrimSpace(arguments.FolderID)
	if folderID == "" || len(folderID) > 128 || !safeName.MatchString(folderID) {
		return rejected("folder_id_invalid", "folder ID is invalid")
	}
	canonicalPath, validation := canonicalDirectory(arguments.Path)
	if validation != nil {
		return *validation
	}
	folders, err := s.client.Folders(ctx)
	if err != nil {
		return ActionResult{Error: publicError(err)}
	}
	if result := validateUnusedFolder(folderID, canonicalPath, folders); result != nil {
		return *result
	}
	devices, err := s.client.Devices(ctx)
	if err != nil {
		return ActionResult{Error: publicError(err)}
	}
	pending, err := s.client.PendingFolders(ctx)
	if err != nil {
		return ActionResult{Error: publicError(err)}
	}
	selected, validation := validateSelectedDevices(arguments, devices, pending)
	if validation != nil {
		return *validation
	}
	defaults, err := s.client.DefaultFolder(ctx)
	if err != nil {
		return ActionResult{Error: publicError(err)}
	}
	label := strings.TrimSpace(arguments.Label)
	if label == "" && arguments.PendingDeviceID != "" {
		label = pending[folderID].OfferedBy[arguments.PendingDeviceID].Label
	}
	if label == "" {
		label = filepath.Base(canonicalPath)
	}
	defaults["id"] = folderID
	defaults["label"] = boundedLabel(label)
	defaults["path"] = canonicalPath
	defaults["paused"] = false
	defaults["devices"] = folderDevices(s.Current().State.Identity.DeviceID, selected)
	if err := s.client.AddFolder(ctx, defaults); err != nil {
		return s.afterAmbiguousMutation(ctx, err)
	}
	result := s.refreshAfterMutation(ctx)
	result.Data = map[string]string{"folderId": folderID}
	return result
}

func (s *Session) suggestFolderID(ctx context.Context) ActionResult {
	if result := s.requireOnline(); result != nil {
		return *result
	}
	suggestion, err := s.client.RandomString(ctx, 10)
	if err != nil {
		return ActionResult{Error: publicError(err)}
	}
	suggestion = strings.ToLower(strings.TrimSpace(suggestion))
	if len(suggestion) != 10 || !safeName.MatchString(suggestion) {
		return rejected("suggestion_invalid", "Syncthing returned an invalid folder ID")
	}
	return ActionResult{OK: true, Revision: s.Current().Revision,
		Data: map[string]string{"folderId": suggestion}}
}

func (s *Session) setWebUITheme(ctx context.Context, theme string) ActionResult {
	if result := s.requireOnline(); result != nil {
		return *result
	}
	theme = strings.TrimSpace(theme)
	if theme == "" || len(theme) > 64 || !safeName.MatchString(theme) {
		return rejected("theme_invalid", "Web UI theme name is invalid")
	}
	setErr := s.client.SetGUITheme(ctx, theme)
	if setErr != nil && !ambiguousMutation(setErr) {
		return ActionResult{Error: publicError(setErr)}
	}
	for attempt := 0; attempt < 6; attempt++ {
		gui, err := s.client.GUIConfig(ctx)
		if err == nil && gui.Theme == theme {
			return s.refreshAfterMutation(ctx)
		}
		select {
		case <-ctx.Done():
			return rejected("canceled", "theme verification was canceled")
		case <-time.After(time.Duration(attempt+1) * 100 * time.Millisecond):
		}
	}
	return rejected("theme_unverified", "Syncthing did not retain the requested Web UI theme")
}

func (s *Session) verifiedFolder(
	ctx context.Context,
	folderID string,
) (*Folder, syncthing.Folder, ActionResult) {
	if result := s.requireOnline(); result != nil {
		return nil, syncthing.Folder{}, *result
	}
	folderID = strings.TrimSpace(folderID)
	snapshotFolder := findFolder(s.Current().State.Folders, folderID)
	if snapshotFolder == nil {
		return nil, syncthing.Folder{}, rejected("folder_missing", "folder is no longer configured")
	}
	current, err := s.client.Folder(ctx, folderID)
	if err != nil {
		return nil, syncthing.Folder{}, ActionResult{Error: publicError(err)}
	}
	if current.ID != snapshotFolder.ID || current.Path != snapshotFolder.Path {
		return nil, syncthing.Folder{}, rejected("folder_changed", "folder changed before the action")
	}
	return snapshotFolder, current, ActionResult{}
}

func (s *Session) requireOnline() *ActionResult {
	if s.Current().State.Connection.Online {
		return nil
	}
	result := rejected("offline", "Syncthing is not online")
	return &result
}

func (s *Session) refreshAfterMutation(ctx context.Context) ActionResult {
	published, err := s.Refresh(ctx)
	if err != nil {
		return ActionResult{Revision: published.Revision, Error: publicError(err)}
	}
	return ActionResult{OK: true, Revision: published.Revision}
}

func (s *Session) afterAmbiguousMutation(ctx context.Context, err error) ActionResult {
	if ambiguousMutation(err) {
		published, _ := s.Refresh(ctx)
		return ActionResult{Revision: published.Revision, Error: publicError(err)}
	}
	return ActionResult{Error: publicError(err)}
}

func ambiguousMutation(err error) bool {
	var target *syncthing.Error
	return errors.As(err, &target) &&
		(target.Code == syncthing.ErrorConnection || target.Code == syncthing.ErrorTimeout)
}

func (s *Session) publishMutation(mutation Mutation, publish func(PublishedSnapshot)) {
	s.stateMu.Lock()
	if s.current.Revision != 0 {
		s.current.State.Mutation = mutation
		s.current.Revision++
	}
	published := clonePublished(s.current)
	s.stateMu.Unlock()
	if publish != nil && published.Revision != 0 {
		publish(published)
	}
}

func (s *Session) finishMutation(
	action string,
	requestID string,
	result ActionResult,
	publish func(PublishedSnapshot),
) ActionResult {
	mutation := Mutation{ID: boundedIdentifier(requestID),
		Action: boundedIdentifier(action), Error: result.Error}
	if data, ok := result.Data.(map[string]string); ok {
		mutation.Suggestion = boundedIdentifier(data["folderId"])
	}
	s.publishMutation(mutation, publish)
	result.Revision = s.Current().Revision
	return result
}

func findFolder(folders []Folder, folderID string) *Folder {
	for index := range folders {
		if folders[index].ID == folderID {
			copy := folders[index]
			return &copy
		}
	}
	return nil
}

func canonicalDirectory(path string) (string, *ActionResult) {
	path = strings.TrimSpace(path)
	if !filepath.IsAbs(path) {
		result := rejected("path_invalid", "folder path must be absolute")
		return "", &result
	}
	resolved, err := filepath.EvalSymlinks(filepath.Clean(path))
	if err != nil {
		result := rejected("path_missing", "folder path does not exist")
		return "", &result
	}
	info, err := os.Stat(resolved)
	if err != nil || !info.IsDir() {
		result := rejected("path_invalid", "folder path is not a directory")
		return "", &result
	}
	return resolved, nil
}

func validateUnusedFolder(folderID, path string, folders []syncthing.Folder) *ActionResult {
	for _, folder := range folders {
		if folder.ID == folderID {
			result := rejected("folder_exists", "folder ID is already configured")
			return &result
		}
		configured := filepath.Clean(folder.Path)
		if !filepath.IsAbs(configured) {
			continue
		}
		if resolved, err := filepath.EvalSymlinks(configured); err == nil {
			configured = resolved
		}
		if pathsOverlap(path, configured) {
			result := rejected("path_overlap", "folder path overlaps an existing folder")
			return &result
		}
	}
	return nil
}

func pathsOverlap(first, second string) bool {
	for _, pair := range [][2]string{{first, second}, {second, first}} {
		relative, err := filepath.Rel(pair[0], pair[1])
		if err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(os.PathSeparator)) {
			return true
		}
	}
	return false
}

func validateSelectedDevices(
	arguments ActionArguments,
	devices []syncthing.Device,
	pending syncthing.PendingFolders,
) ([]string, *ActionResult) {
	available := make(map[string]syncthing.Device, len(devices))
	for _, device := range devices {
		available[device.DeviceID] = device
	}
	selectedSet := make(map[string]struct{}, len(arguments.DeviceIDs))
	for _, deviceID := range arguments.DeviceIDs {
		device, exists := available[deviceID]
		if !exists || device.Untrusted {
			result := rejected("device_invalid", "selected device is unavailable or untrusted")
			return nil, &result
		}
		selectedSet[deviceID] = struct{}{}
	}
	if arguments.PendingDeviceID != "" {
		offer, exists := pending[arguments.FolderID].OfferedBy[arguments.PendingDeviceID]
		if !exists {
			result := rejected("offer_missing", "selected folder offer is no longer available")
			return nil, &result
		}
		if offer.ReceiveEncrypted || offer.RemoteEncrypted {
			result := rejected("offer_encrypted", "encrypted folder offers are unsupported")
			return nil, &result
		}
		if _, selected := selectedSet[arguments.PendingDeviceID]; !selected {
			result := rejected("offer_device_missing", "offering device must remain selected")
			return nil, &result
		}
	}
	selected := make([]string, 0, len(selectedSet))
	for deviceID := range selectedSet {
		selected = append(selected, deviceID)
	}
	sort.Strings(selected)
	return selected, nil
}

func folderDevices(localDeviceID string, selected []string) []map[string]string {
	ids := append([]string{localDeviceID}, selected...)
	seen := make(map[string]struct{}, len(ids))
	result := make([]map[string]string, 0, len(ids))
	for _, deviceID := range ids {
		if deviceID == "" {
			continue
		}
		if _, exists := seen[deviceID]; exists {
			continue
		}
		seen[deviceID] = struct{}{}
		result = append(result, map[string]string{"deviceID": deviceID})
	}
	return result
}

package session

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
)

type actionAPI struct {
	mu                sync.Mutex
	folders           map[string]syncthing.Folder
	devices           []syncthing.Device
	pending           syncthing.PendingFolders
	theme             string
	rescans           int
	lastAdd           syncthing.FolderConfig
	dropThemeResponse bool
	rescanStarted     chan struct{}
	rescanRelease     chan struct{}
}

func TestRescanPublishesBusyBeforeSlowRequestCompletes(t *testing.T) {
	directory := t.TempDir()
	api := &actionAPI{
		folders: map[string]syncthing.Folder{"folder": {
			ID: "folder", Label: "Folder", Path: directory,
		}},
		devices:       []syncthing.Device{{DeviceID: "LOCAL"}},
		pending:       syncthing.PendingFolders{},
		theme:         "default",
		rescanStarted: make(chan struct{}, 1),
		rescanRelease: make(chan struct{}, 1),
	}
	t.Cleanup(func() {
		select {
		case api.rescanRelease <- struct{}{}:
		default:
		}
	})
	coreSession := newActionSession(t, api)
	if _, err := coreSession.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}

	published := make(chan PublishedSnapshot, 8)
	results := make(chan ActionResult, 1)
	go func() {
		results <- coreSession.Act(context.Background(), "folder.rescan",
			ActionArguments{FolderID: "folder"}, "slow-rescan",
			func(snapshot PublishedSnapshot) { published <- snapshot })
	}()

	select {
	case snapshot := <-published:
		mutation := snapshot.State.Mutation
		if !mutation.Busy || mutation.ID != "slow-rescan" ||
			mutation.Action != "folder.rescan" {
			t.Fatalf("first rescan state is not busy: %#v", mutation)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("rescan busy state was not published immediately")
	}
	select {
	case <-api.rescanStarted:
	case <-time.After(2 * time.Second):
		t.Fatal("rescan request did not start")
	}
	select {
	case result := <-results:
		t.Fatalf("rescan completed before release: %#v", result)
	default:
	}
	api.rescanRelease <- struct{}{}

	select {
	case result := <-results:
		if !result.OK {
			t.Fatalf("rescan failed after release: %#v", result)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("rescan did not complete after release")
	}
	for {
		select {
		case snapshot := <-published:
			if !snapshot.State.Mutation.Busy {
				return
			}
		case <-time.After(2 * time.Second):
			t.Fatal("rescan terminal state was not published")
		}
	}
}

func TestFolderActionsAndMutationState(t *testing.T) {
	directory := t.TempDir()
	existing := filepath.Join(directory, "existing")
	added := filepath.Join(directory, "added")
	if err := os.MkdirAll(existing, 0o700); err != nil {
		t.Fatal(err)
	}
	api := &actionAPI{
		folders: map[string]syncthing.Folder{"folder": {
			ID: "folder", Label: "Existing", Path: existing, Paused: false,
		}},
		devices: []syncthing.Device{{DeviceID: "LOCAL", Name: "local"},
			{DeviceID: "REMOTE", Name: "remote"}},
		pending: syncthing.PendingFolders{"offer": {OfferedBy: map[string]syncthing.FolderOffer{
			"REMOTE": {Label: "Offered"},
		}}},
		theme: "default",
	}
	coreSession := newActionSession(t, api)
	if _, err := coreSession.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}

	var published []PublishedSnapshot
	publish := func(snapshot PublishedSnapshot) { published = append(published, snapshot) }
	result := coreSession.Act(context.Background(), "folder.pause",
		ActionArguments{FolderID: "folder"}, "1", publish)
	if !result.OK || !api.folder("folder").Paused {
		t.Fatalf("pause failed: %#v", result)
	}
	if len(published) < 2 || !published[0].State.Mutation.Busy ||
		published[len(published)-1].State.Mutation.Busy {
		t.Fatalf("mutation lifecycle was not published: %#v", published)
	}

	result = coreSession.Act(context.Background(), "folder.resume",
		ActionArguments{FolderID: "folder"}, "2", nil)
	if !result.OK || api.folder("folder").Paused {
		t.Fatalf("resume failed: %#v", result)
	}
	result = coreSession.Act(context.Background(), "folder.rescan",
		ActionArguments{FolderID: "folder"}, "3", nil)
	if !result.OK {
		t.Fatalf("rescan failed: %#v", result)
	}
	result = coreSession.Act(context.Background(), "folder.rescan-all",
		ActionArguments{}, "4", nil)
	if !result.OK || api.rescanCount() != 2 {
		t.Fatalf("rescan-all failed: %#v count=%d", result, api.rescanCount())
	}
	api.setFolderPaused("folder", true)
	result = coreSession.Act(context.Background(), "folder.rescan-all",
		ActionArguments{}, "all-paused", nil)
	if result.OK || result.Error == nil || result.Error.Code != "folder_paused" ||
		api.rescanCount() != 2 {
		t.Fatalf("all-paused rescan was accepted: %#v", result)
	}
	api.setFolderPaused("folder", false)

	if err := os.WriteFile(filepath.Join(existing, "retained.txt"), []byte("retained"), 0o600); err != nil {
		t.Fatal(err)
	}
	if result = coreSession.Act(context.Background(), "folder.pause",
		ActionArguments{FolderID: "folder"}, "5", nil); !result.OK {
		t.Fatal(result.Error)
	}
	result = coreSession.Act(context.Background(), "folder.forget",
		ActionArguments{FolderID: "folder"}, "6", nil)
	if !result.OK || api.hasFolder("folder") {
		t.Fatalf("forget failed: %#v", result)
	}
	if _, err := os.Stat(filepath.Join(existing, "retained.txt")); err != nil {
		t.Fatalf("forget removed local data: %v", err)
	}

	if err := os.MkdirAll(added, 0o700); err != nil {
		t.Fatal(err)
	}
	result = coreSession.Act(context.Background(), "folder.add-existing",
		ActionArguments{FolderID: "offer", Path: added, DeviceIDs: []string{"REMOTE"},
			PendingDeviceID: "REMOTE"}, "7", nil)
	if !result.OK || !api.hasFolder("offer") {
		t.Fatalf("add existing failed: %#v", result)
	}
	addedDevices := api.addedDeviceIDs()
	if strings.Join(addedDevices, ",") != "LOCAL,REMOTE" {
		t.Fatalf("unexpected added devices: %v", addedDevices)
	}

	result = coreSession.Act(context.Background(), "folder.add-existing",
		ActionArguments{FolderID: "offer", Path: added}, "8", nil)
	if result.OK || result.Error == nil || result.Error.Code != "folder_exists" {
		t.Fatalf("duplicate folder accepted: %#v", result)
	}
	overlap := filepath.Join(added, "nested")
	if err := os.Mkdir(overlap, 0o700); err != nil {
		t.Fatal(err)
	}
	result = coreSession.Act(context.Background(), "folder.add-existing",
		ActionArguments{FolderID: "overlap", Path: overlap}, "9", nil)
	if result.OK || result.Error == nil || result.Error.Code != "path_overlap" {
		t.Fatalf("overlapping path accepted: %#v", result)
	}
}

func TestSuggestionThemeAndActionShape(t *testing.T) {
	api := &actionAPI{folders: map[string]syncthing.Folder{},
		devices: []syncthing.Device{{DeviceID: "LOCAL"}},
		pending: syncthing.PendingFolders{}, theme: "default"}
	coreSession := newActionSession(t, api)
	if _, err := coreSession.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	result := coreSession.Act(context.Background(), "folder.rescan-all",
		ActionArguments{}, "empty-rescan", nil)
	if result.OK || result.Error == nil || result.Error.Code != "folder_missing" {
		t.Fatalf("empty rescan-all was accepted: %#v", result)
	}
	result = coreSession.Act(context.Background(), "folder.suggest-id",
		ActionArguments{}, "1", nil)
	data, ok := result.Data.(map[string]string)
	if !result.OK || !ok || data["folderId"] != "abcdefghij" {
		t.Fatalf("suggestion failed: %#v", result)
	}
	result = coreSession.Act(context.Background(), "webui.set-theme",
		ActionArguments{Theme: "syncthing-omarchy"}, "2", nil)
	if !result.OK || api.currentTheme() != "syncthing-omarchy" {
		t.Fatalf("theme action failed: %#v", result)
	}
	api.setDropThemeResponse(true)
	result = coreSession.Act(context.Background(), "webui.set-theme",
		ActionArguments{Theme: "default"}, "drop", nil)
	if !result.OK || api.currentTheme() != "default" {
		t.Fatalf("theme response-drop recovery failed: %#v", result)
	}
	result = coreSession.Act(context.Background(), "folder.rescan-all",
		ActionArguments{Theme: "unexpected"}, "3", nil)
	if result.OK || result.Error == nil || result.Error.Code != "invalid_action" {
		t.Fatalf("irrelevant action arguments were accepted: %#v", result)
	}
}

func TestAddValidationRejectsUnsafeInputs(t *testing.T) {
	devices := []syncthing.Device{{DeviceID: "TRUSTED"},
		{DeviceID: "UNTRUSTED", Untrusted: true}}
	pending := syncthing.PendingFolders{"offer": {OfferedBy: map[string]syncthing.FolderOffer{
		"TRUSTED": {ReceiveEncrypted: true},
	}}}
	if _, result := validateSelectedDevices(ActionArguments{
		FolderID: "offer", DeviceIDs: []string{"UNTRUSTED"}}, devices, pending); result == nil || result.Error == nil || result.Error.Code != "device_invalid" {
		t.Fatalf("untrusted device accepted: %#v", result)
	}
	if _, result := validateSelectedDevices(ActionArguments{
		FolderID: "offer", DeviceIDs: []string{"TRUSTED"}, PendingDeviceID: "TRUSTED"},
		devices, pending); result == nil || result.Error == nil ||
		result.Error.Code != "offer_encrypted" {
		t.Fatalf("encrypted offer accepted: %#v", result)
	}
	if _, result := validateSelectedDevices(ActionArguments{
		FolderID: "missing", DeviceIDs: []string{"TRUSTED"}, PendingDeviceID: "TRUSTED"},
		devices, pending); result == nil || result.Error == nil ||
		result.Error.Code != "offer_missing" {
		t.Fatalf("missing offer accepted: %#v", result)
	}
	if _, result := canonicalDirectory("relative/path"); result == nil ||
		result.Error == nil || result.Error.Code != "path_invalid" {
		t.Fatalf("relative path accepted: %#v", result)
	}
}

func newActionSession(t *testing.T, api *actionAPI) *Session {
	t.Helper()
	server := httptest.NewServer(api)
	t.Cleanup(server.Close)
	configPath := filepath.Join(t.TempDir(), "config.xml")
	config := fmt.Sprintf(`<configuration><gui tls="false"><address>%s</address><apikey>%s</apikey></gui></configuration>`,
		strings.TrimPrefix(server.URL, "http://"), sessionTestKey)
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	coreSession, err := New(context.Background(), Config{
		Discovery: syncthing.DiscoveryOptions{ConfigPath: configPath},
	})
	if err != nil {
		t.Fatal(err)
	}
	return coreSession
}

func (a *actionAPI) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if request.URL.Path != "/rest/noauth/health" &&
		request.Header.Get("X-API-Key") != sessionTestKey {
		http.Error(writer, "unauthorized", http.StatusUnauthorized)
		return
	}
	switch {
	case request.URL.Path == "/rest/noauth/health":
		a.write(writer, `{"status":"OK"}`)
	case request.URL.Path == "/rest/system/status":
		a.write(writer, `{"myID":"LOCAL"}`)
	case request.URL.Path == "/rest/system/version":
		a.write(writer, `{"version":"v2.1.3"}`)
	case request.URL.Path == "/rest/config/devices":
		a.writeValue(writer, a.devices)
	case request.URL.Path == "/rest/config/folders" && request.Method == http.MethodGet:
		folders := make([]syncthing.Folder, 0, len(a.folders))
		for _, folder := range a.folders {
			folders = append(folders, folder)
		}
		a.writeValue(writer, folders)
	case request.URL.Path == "/rest/config/folders" && request.Method == http.MethodPost:
		var config syncthing.FolderConfig
		if json.NewDecoder(request.Body).Decode(&config) != nil {
			http.Error(writer, "bad config", http.StatusBadRequest)
			return
		}
		a.lastAdd = config
		folder := syncthing.Folder{ID: config["id"].(string), Label: config["label"].(string),
			Path: config["path"].(string), Paused: false}
		a.folders[folder.ID] = folder
		writer.WriteHeader(http.StatusOK)
	case strings.HasPrefix(request.URL.Path, "/rest/config/folders/"):
		id := strings.TrimPrefix(request.URL.Path, "/rest/config/folders/")
		folder, exists := a.folders[id]
		if !exists {
			http.NotFound(writer, request)
			return
		}
		switch request.Method {
		case http.MethodGet:
			a.writeValue(writer, folder)
		case http.MethodPatch:
			var patch map[string]bool
			_ = json.NewDecoder(request.Body).Decode(&patch)
			folder.Paused = patch["paused"]
			a.folders[id] = folder
			writer.WriteHeader(http.StatusOK)
		case http.MethodDelete:
			delete(a.folders, id)
			writer.WriteHeader(http.StatusOK)
		}
	case request.URL.Path == "/rest/system/connections":
		a.write(writer, `{"connections":{}}`)
	case request.URL.Path == "/rest/db/status":
		a.write(writer, `{"state":"idle"}`)
	case request.URL.Path == "/rest/folder/errors":
		a.write(writer, `{"errors":[]}`)
	case request.URL.Path == "/rest/cluster/pending/folders":
		a.writeValue(writer, a.pending)
	case request.URL.Path == "/rest/config/gui" && request.Method == http.MethodGet:
		a.writeValue(writer, syncthing.GUIConfig{Theme: a.theme})
	case request.URL.Path == "/rest/config/gui" && request.Method == http.MethodPatch:
		var patch map[string]string
		_ = json.NewDecoder(request.Body).Decode(&patch)
		a.theme = patch["theme"]
		if a.dropThemeResponse {
			a.dropThemeResponse = false
			connection, _, err := writer.(http.Hijacker).Hijack()
			if err == nil {
				_ = connection.Close()
			}
			return
		}
		writer.WriteHeader(http.StatusOK)
	case request.URL.Path == "/rest/system/paths":
		a.write(writer, `{"guiAssets":"/tmp/gui","baseDir-userHome":"/tmp"}`)
	case request.URL.Path == "/rest/config/defaults/folder":
		a.write(writer, `{"id":"","label":"","path":"","paused":false,"devices":[]}`)
	case request.URL.Path == "/rest/svc/random/string":
		a.write(writer, `{"random":"ABCDEFGHIJ"}`)
	case request.URL.Path == "/rest/db/scan":
		a.rescans++
		if a.rescanStarted != nil {
			select {
			case a.rescanStarted <- struct{}{}:
			default:
			}
		}
		if a.rescanRelease != nil {
			<-a.rescanRelease
		}
		writer.WriteHeader(http.StatusOK)
	case request.URL.Path == "/rest/db/file":
		name := request.URL.Query().Get("file")
		switch name {
		case "old.txt":
			a.write(writer, `{"local":{"name":"old.txt","type":"FILE_INFO_TYPE_FILE","deleted":true}}`)
		case "directory":
			a.write(writer, `{"local":{"name":"directory","type":"FILE_INFO_TYPE_DIRECTORY","deleted":false}}`)
		default:
			a.writeValue(writer, map[string]any{"local": map[string]any{
				"name": name, "type": "FILE_INFO_TYPE_FILE", "deleted": false,
			}})
		}
	default:
		http.NotFound(writer, request)
	}
}

func (a *actionAPI) folder(id string) syncthing.Folder {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.folders[id]
}

func (a *actionAPI) hasFolder(id string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	_, exists := a.folders[id]
	return exists
}

func (a *actionAPI) setFolderPaused(id string, paused bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	folder := a.folders[id]
	folder.Paused = paused
	a.folders[id] = folder
}

func (a *actionAPI) rescanCount() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.rescans
}

func (a *actionAPI) currentTheme() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.theme
}

func (a *actionAPI) setDropThemeResponse(value bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.dropThemeResponse = value
}

func (a *actionAPI) addedDeviceIDs() []string {
	a.mu.Lock()
	defer a.mu.Unlock()
	values, _ := a.lastAdd["devices"].([]any)
	ids := make([]string, 0, len(values))
	for _, value := range values {
		device, _ := value.(map[string]any)
		id, _ := device["deviceID"].(string)
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

func (a *actionAPI) write(writer http.ResponseWriter, value string) {
	writer.Header().Set("Content-Type", "application/json")
	_, _ = writer.Write([]byte(value))
}

func (a *actionAPI) writeValue(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(writer).Encode(value)
}

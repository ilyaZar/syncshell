package session

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
	"github.com/omarchy-QOL/syncshell/core/internal/systemduser"
)

const sessionTestKey = "session-test-key"

type testAPI struct {
	globalFiles  atomic.Int32
	rescans      atomic.Int32
	inFlight     atomic.Int32
	maxInFlight  atomic.Int32
	unauthorized atomic.Bool
}

func TestRefreshIsDeterministicAndRevisioned(t *testing.T) {
	api := &testAPI{}
	api.globalFiles.Store(2)
	coreSession := newTestSession(t, api, "inactive", "LOCAL-ID")
	first, err := coreSession.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	second, err := coreSession.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if first.Revision != 1 || second.Revision != first.Revision {
		t.Fatalf("unchanged state advanced revision: first=%d second=%d",
			first.Revision, second.Revision)
	}
	if !first.State.Connection.Online || first.State.Identity.DeviceID != "LOCAL-ID" {
		t.Fatalf("unexpected online state: %#v", first.State)
	}
	if len(first.State.Devices) != 2 || !first.State.Devices[1].Connected {
		t.Fatalf("device normalization failed: %#v", first.State.Devices)
	}
	if first.State.Lifecycle.Classification != "external" ||
		first.State.Lifecycle.CanControl {
		t.Fatalf("inactive unit suppressed API-first state: %#v", first.State.Lifecycle)
	}

	api.globalFiles.Store(3)
	third, err := coreSession.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if third.Revision != first.Revision+1 || third.State.Folders[0].Status.GlobalFiles != 3 {
		t.Fatalf("changed state did not advance revision: %#v", third)
	}
}

func TestTrustedActiveBindingIsManaged(t *testing.T) {
	coreSession := newTestSession(t, &testAPI{}, "active", "LOCAL-ID")
	published, err := coreSession.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	lifecycle := published.State.Lifecycle
	if lifecycle.Classification != "managed" || !lifecycle.CanControl || !lifecycle.TargetMatch {
		t.Fatalf("trusted active binding was not managed: %#v", lifecycle)
	}
}

func TestExternalClassificationSurvivesTransientAPILoss(t *testing.T) {
	api := &testAPI{}
	coreSession := newTestSession(t, api, "inactive", "LOCAL-ID")
	initial, err := coreSession.Refresh(context.Background())
	if err != nil || initial.State.Lifecycle.Classification != "external" {
		t.Fatalf("external initialization failed: %#v %v", initial, err)
	}
	api.unauthorized.Store(true)
	lost, err := coreSession.Refresh(context.Background())
	if err == nil || lost.State.Lifecycle.Classification != "external" ||
		lost.State.Lifecycle.CanControl || lost.State.Lifecycle.CanStart {
		t.Fatalf("API loss exposed lifecycle controls: %#v %v", lost, err)
	}
}

func TestExpectedIdentityMismatchRemovesAuthority(t *testing.T) {
	coreSession := newTestSession(t, &testAPI{}, "active", "OTHER-ID")
	published, err := coreSession.Refresh(context.Background())
	if err == nil {
		t.Fatal("identity mismatch succeeded")
	}
	if published.State.Connection.Online || published.State.Connection.Error == nil ||
		published.State.Connection.Error.Code != "identity" || published.State.Lifecycle.CanControl {
		t.Fatalf("identity mismatch retained authority: %#v", published.State)
	}
}

func TestUnauthorizedResponseIsSanitized(t *testing.T) {
	api := &testAPI{}
	api.unauthorized.Store(true)
	coreSession := newTestSession(t, api, "active", "LOCAL-ID")
	published, err := coreSession.Refresh(context.Background())
	if err == nil || published.State.Connection.Error == nil {
		t.Fatal("unauthorized response succeeded")
	}
	encoded := fmt.Sprintf("%#v %v", published, err)
	if strings.Contains(encoded, sessionTestKey) {
		t.Fatal("public state exposed the API key")
	}
}

func TestRescanIsValidatedAndSerialized(t *testing.T) {
	api := &testAPI{}
	coreSession := newTestSession(t, api, "active", "LOCAL-ID")
	if _, err := coreSession.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if result := coreSession.Act(context.Background(), "folder.rescan",
		ActionArguments{FolderID: "missing"}, "missing", nil); result.OK ||
		result.Error == nil || result.Error.Code != "folder_missing" {
		t.Fatalf("missing folder result: %#v", result)
	}

	var wait sync.WaitGroup
	results := make(chan ActionResult, 2)
	for range 2 {
		wait.Add(1)
		go func() {
			defer wait.Done()
			results <- coreSession.Act(context.Background(), "folder.rescan",
				ActionArguments{FolderID: "folder"}, "concurrent", nil)
		}()
	}
	wait.Wait()
	close(results)
	for result := range results {
		if !result.OK {
			t.Fatalf("rescan failed: %#v", result)
		}
	}
	if api.rescans.Load() != 2 || api.maxInFlight.Load() != 1 {
		t.Fatalf("rescans=%d max in flight=%d", api.rescans.Load(), api.maxInFlight.Load())
	}
}

func TestConfigureValidatesHostNeutralValues(t *testing.T) {
	coreSession := newTestSession(t, &testAPI{}, "inactive", "LOCAL-ID")
	zero := 0
	if result := coreSession.Configure(OperationalConfig{ProbeIntervalSeconds: &zero}); result.OK || result.Error == nil {
		t.Fatalf("invalid interval accepted: %#v", result)
	}
	seconds := 3
	invalidState := "invalid"
	if result := coreSession.Configure(OperationalConfig{
		ProbeIntervalSeconds: &seconds, DesiredServiceState: &invalidState}); result.OK || coreSession.ProbeInterval() != 15*time.Second {
		t.Fatalf("invalid config was partially applied: %#v", result)
	}
	before, err := coreSession.Refresh(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	state := "disabled"
	if result := coreSession.Configure(OperationalConfig{
		ProbeIntervalSeconds: &seconds, DesiredServiceState: &state}); !result.OK {
		t.Fatalf("valid config rejected: %#v", result)
	}
	if coreSession.ProbeInterval() != 3*time.Second {
		t.Fatalf("probe interval is %v", coreSession.ProbeInterval())
	}
	after := coreSession.Current()
	if after.Revision != before.Revision+1 ||
		after.State.Lifecycle.DesiredState != "disabled" {
		t.Fatalf("desired lifecycle state was not published: %#v", after)
	}
}

func TestConfigureSupportsConcurrentUpdates(t *testing.T) {
	coreSession := newTestSession(t, &testAPI{}, "inactive", "LOCAL-ID")
	if _, err := coreSession.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	var wait sync.WaitGroup
	for index := 0; index < 32; index++ {
		wait.Add(1)
		go func(index int) {
			defer wait.Done()
			seconds := index%10 + 1
			state := "enabled"
			if index%2 == 0 {
				state = "disabled"
			}
			if result := coreSession.Configure(OperationalConfig{
				ProbeIntervalSeconds: &seconds, DesiredServiceState: &state}); !result.OK {
				t.Errorf("configure failed: %#v", result)
			}
		}(index)
	}
	wait.Wait()
	interval := coreSession.ProbeInterval()
	if interval < time.Second || interval > 10*time.Second {
		t.Fatalf("invalid final interval: %v", interval)
	}
}

func newTestSession(t *testing.T, api *testAPI, active, expectedID string) *Session {
	t.Helper()
	server := httptest.NewServer(api)
	t.Cleanup(server.Close)
	configPath := filepath.Join(t.TempDir(), "config.xml")
	address := strings.TrimPrefix(server.URL, "http://")
	config := fmt.Sprintf(`<configuration><gui tls="false"><address>%s</address><apikey>%s</apikey></gui></configuration>`,
		address, sessionTestKey)
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	systemctl := filepath.Join(t.TempDir(), "systemctl")
	script := "#!/bin/sh\nprintf '%s\\n' 'LoadState=loaded' 'ActiveState=" + active +
		"' 'UnitFileState=enabled' 'FragmentPath=/usr/lib/systemd/user/syncthing.service' " +
		"'ExecStart=/usr/bin/syncthing serve --config=" + configPath + "' 'Environment='\n"
	if err := os.WriteFile(systemctl, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	coreSession, err := New(context.Background(), Config{
		Discovery: syncthing.DiscoveryOptions{ConfigPath: configPath,
			ExpectedDeviceID: expectedID},
		Lifecycle: systemduser.Binding{Authorized: true, Unit: "syncthing.service",
			ConfigPath: configPath},
		SystemdCommand: systemctl,
	})
	if err != nil {
		t.Fatal(err)
	}
	return coreSession
}

func (a *testAPI) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	if request.URL.Path != "/rest/noauth/health" &&
		(a.unauthorized.Load() || request.Header.Get("X-API-Key") != sessionTestKey) {
		http.Error(writer, "unauthorized "+sessionTestKey, http.StatusUnauthorized)
		return
	}
	switch request.URL.Path {
	case "/rest/noauth/health":
		writeSessionJSON(writer, `{"status":"OK"}`)
	case "/rest/system/status":
		writeSessionJSON(writer, `{"myID":"LOCAL-ID"}`)
	case "/rest/system/version":
		writeSessionJSON(writer, `{"version":"v2.1.3"}`)
	case "/rest/config/devices":
		writeSessionJSON(writer,
			`[{"deviceID":"REMOTE","name":"remote"},{"deviceID":"LOCAL-ID","name":"local"}]`)
	case "/rest/config/folders":
		writeSessionJSON(writer,
			`[{"id":"folder","label":"Folder","path":"/tmp/folder","paused":false,"devices":[{"deviceID":"REMOTE"}]}]`)
	case "/rest/config/folders/folder":
		writeSessionJSON(writer,
			`{"id":"folder","label":"Folder","path":"/tmp/folder","paused":false,"devices":[{"deviceID":"REMOTE"}]}`)
	case "/rest/system/connections":
		writeSessionJSON(writer, `{"connections":{"REMOTE":{"connected":true}}}`)
	case "/rest/db/status":
		writeSessionJSON(writer, fmt.Sprintf(
			`{"state":"idle","globalFiles":%d,"globalBytes":9}`, a.globalFiles.Load()))
	case "/rest/folder/errors":
		writeSessionJSON(writer, `{"errors":[]}`)
	case "/rest/cluster/pending/folders":
		writeSessionJSON(writer, `{}`)
	case "/rest/config/gui":
		writeSessionJSON(writer, `{"theme":"default"}`)
	case "/rest/system/paths":
		writeSessionJSON(writer, `{"guiAssets":"/tmp/gui","baseDir-userHome":"/tmp"}`)
	case "/rest/db/scan":
		current := a.inFlight.Add(1)
		for {
			maximum := a.maxInFlight.Load()
			if current <= maximum || a.maxInFlight.CompareAndSwap(maximum, current) {
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
		a.inFlight.Add(-1)
		a.rescans.Add(1)
		writer.WriteHeader(http.StatusOK)
	default:
		http.NotFound(writer, request)
	}
}

func writeSessionJSON(writer http.ResponseWriter, value string) {
	writer.Header().Set("Content-Type", "application/json")
	_, _ = writer.Write([]byte(value))
}

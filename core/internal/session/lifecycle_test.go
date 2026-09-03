package session

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
	"github.com/omarchy-QOL/syncshell/core/internal/systemduser"
)

func TestLifecycleActionsRequireAndRetainTargetAuthority(t *testing.T) {
	directory := t.TempDir()
	activeFile := filepath.Join(directory, "active")
	enabledFile := filepath.Join(directory, "enabled")
	writeState(t, activeFile, "inactive")
	writeState(t, enabledFile, "disabled")

	server := httptest.NewServer(lifecycleAPI{activeFile: activeFile})
	defer server.Close()
	configPath := filepath.Join(directory, "config.xml")
	config := fmt.Sprintf(`<configuration><gui tls="false"><address>%s</address><apikey>%s</apikey></gui></configuration>`,
		strings.TrimPrefix(server.URL, "http://"), sessionTestKey)
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	command := lifecycleSystemctl(t, directory, configPath, activeFile, enabledFile)
	coreSession, err := New(context.Background(), Config{
		Discovery: syncthing.DiscoveryOptions{ConfigPath: configPath},
		Lifecycle: systemduser.Binding{Authorized: true, Unit: "syncthing.service",
			ConfigPath: configPath},
		SystemdCommand: command,
	})
	if err != nil {
		t.Fatal(err)
	}
	published, err := coreSession.Refresh(context.Background())
	if err == nil || !published.State.Lifecycle.CanStart {
		t.Fatalf("offline candidate lacks start authority: %#v %v", published.State, err)
	}

	for _, action := range []string{"start", "enable", "disable", "stop"} {
		result := coreSession.Act(context.Background(), "lifecycle."+action,
			ActionArguments{}, action, nil)
		if !result.OK {
			t.Fatalf("lifecycle %s failed: %#v", action, result)
		}
	}
	if state := readState(t, activeFile); state != "inactive" {
		t.Fatalf("service state is %s", state)
	}
	if state := readState(t, enabledFile); state != "disabled" {
		t.Fatalf("unit-file state is %s", state)
	}

	external, err := New(context.Background(), Config{
		Discovery: syncthing.DiscoveryOptions{ConfigPath: configPath},
	})
	if err != nil {
		t.Fatal(err)
	}
	result := external.Act(context.Background(), "lifecycle.start",
		ActionArguments{}, "forbidden", nil)
	if result.OK || result.Error == nil || result.Error.Code != "lifecycle_forbidden" {
		t.Fatalf("external target gained lifecycle authority: %#v", result)
	}
}

type lifecycleAPI struct{ activeFile string }

func (a lifecycleAPI) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	active, _ := os.ReadFile(a.activeFile)
	if strings.TrimSpace(string(active)) != "active" {
		http.Error(writer, "offline", http.StatusServiceUnavailable)
		return
	}
	switch request.URL.Path {
	case "/rest/noauth/health":
		writeSessionJSON(writer, `{"status":"OK"}`)
	case "/rest/system/status":
		writeSessionJSON(writer, `{"myID":"LOCAL"}`)
	case "/rest/system/version":
		writeSessionJSON(writer, `{"version":"v2.1.3"}`)
	case "/rest/config/devices", "/rest/config/folders":
		writeSessionJSON(writer, `[]`)
	case "/rest/system/connections":
		writeSessionJSON(writer, `{"connections":{}}`)
	case "/rest/cluster/pending/folders":
		writeSessionJSON(writer, `{}`)
	case "/rest/config/gui":
		writeSessionJSON(writer, `{"theme":"default"}`)
	case "/rest/system/paths":
		writeSessionJSON(writer, `{"guiAssets":"/tmp/gui"}`)
	default:
		http.NotFound(writer, request)
	}
}

func lifecycleSystemctl(
	t *testing.T,
	directory string,
	configPath string,
	activeFile string,
	enabledFile string,
) string {
	t.Helper()
	command := filepath.Join(directory, "systemctl")
	script := fmt.Sprintf(`#!/bin/bash
set -euo pipefail
active=$(<%q)
enabled=$(<%q)
case "${2:-}" in
  show)
    printf '%%s\n' 'LoadState=loaded' "ActiveState=$active" \
      "UnitFileState=$enabled" \
      'FragmentPath=/usr/lib/systemd/user/syncthing.service' \
      'ExecStart=/usr/bin/syncthing serve --config=%s' 'Environment='
    ;;
  start) printf 'active\n' >%q ;;
  stop) printf 'inactive\n' >%q ;;
  enable) printf 'enabled\n' >%q ;;
  disable) printf 'disabled\n' >%q ;;
  *) exit 2 ;;
esac
`, activeFile, enabledFile, configPath, activeFile, activeFile, enabledFile, enabledFile)
	if err := os.WriteFile(command, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	return command
}

func writeState(t *testing.T, path, value string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(value+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
}

func readState(t *testing.T, path string) string {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(contents))
}

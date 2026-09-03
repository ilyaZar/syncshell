package systemduser

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestApplyUsesExactAuthorizedUnit(t *testing.T) {
	directory := t.TempDir()
	record := filepath.Join(directory, "record")
	command := filepath.Join(directory, "systemctl")
	script := fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$*\" >>%q\n", record)
	if err := os.WriteFile(command, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	controller := Controller{Command: command}
	for _, action := range []Action{ActionStart, ActionStop, ActionEnable, ActionDisable} {
		if err := controller.Apply(context.Background(), "syncthing.service", action); err != nil {
			t.Fatal(err)
		}
	}
	contents, err := os.ReadFile(record)
	if err != nil {
		t.Fatal(err)
	}
	for _, action := range []Action{ActionStart, ActionStop, ActionEnable, ActionDisable} {
		expected := "--user " + string(action) + " syncthing.service"
		if !strings.Contains(string(contents), expected) {
			t.Fatalf("missing invocation %q in %q", expected, contents)
		}
	}
	if err := controller.Apply(context.Background(), "../bad.service", ActionStart); err == nil {
		t.Fatal("invalid unit action succeeded")
	}
}

func TestProbeClassifications(t *testing.T) {
	config := filepath.Join(t.TempDir(), "config.xml")
	tests := []struct {
		name           string
		active         string
		online         bool
		automatic      bool
		bindingConfig  string
		execStart      string
		classification string
		canControl     bool
		canStart       bool
	}{
		{"managed", "active", true, true, "", "/usr/bin/syncthing serve",
			"managed", true, false},
		{"online inactive is external", "inactive", true, true, "", "/usr/bin/syncthing serve",
			"external", false, false},
		{"offline stopped candidate", "inactive", false, true, "", "/usr/bin/syncthing serve",
			"stopped-candidate", true, true},
		{"active API unavailable", "active", false, true, "", "/usr/bin/syncthing serve",
			"unit-active-api-unavailable", true, false},
		{"explicit matching config", "active", true, false, config,
			"/usr/bin/syncthing serve --config=" + config, "managed", true, false},
		{"explicit mismatched invocation", "active", true, false, config,
			"/usr/bin/syncthing serve --config=/tmp/other.xml", "external", false, false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			command := fakeSystemctl(t, test.active, test.execStart)
			state := (Controller{Command: command}).Probe(context.Background(),
				Binding{Authorized: true, Unit: "syncthing.service", ConfigPath: test.bindingConfig},
				Target{ConfigPath: config,
					Local: true, Automatic: test.automatic}, test.online)
			if state.Classification != test.classification || state.CanControl != test.canControl ||
				state.CanStart != test.canStart {
				t.Fatalf("unexpected state: %#v", state)
			}
		})
	}
}

func TestProbeRequiresExplicitAuthorityAndLocalTarget(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing-systemctl")
	state := (Controller{Command: missing}).Probe(context.Background(),
		Binding{Unit: "syncthing.service"}, Target{Local: true, Automatic: true}, true)
	if state.CanControl || state.Error != "" || state.Authorized {
		t.Fatalf("unauthorized unit affected state: %#v", state)
	}

	command := fakeSystemctl(t, "active", "/usr/bin/syncthing serve")
	state = (Controller{Command: command}).Probe(context.Background(),
		Binding{Authorized: true, Unit: "syncthing.service"},
		Target{ConfigPath: "/tmp/config.xml",
			Local: false, Automatic: true}, true)
	if state.CanControl || state.TargetMatch || state.Classification != "external" {
		t.Fatalf("remote target gained lifecycle authority: %#v", state)
	}
}

func TestProbeRejectsInvalidUnit(t *testing.T) {
	state := (Controller{Command: filepath.Join(t.TempDir(), "missing")}).Probe(
		context.Background(), Binding{Authorized: true, Unit: "../syncthing.service"},
		Target{Local: true, Automatic: true}, false)
	if state.CanControl || state.Error != "" {
		t.Fatalf("invalid unit reached systemctl: %#v", state)
	}
}

func fakeSystemctl(t *testing.T, active, execStart string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "systemctl")
	contents := "#!/bin/sh\n" +
		"printf '%s\\n' 'LoadState=loaded' 'ActiveState=" + active +
		"' 'UnitFileState=enabled' 'FragmentPath=/usr/lib/systemd/user/syncthing.service' " +
		"'ExecStart=" + execStart + "' 'Environment='\n"
	if err := os.WriteFile(path, []byte(contents), 0o700); err != nil {
		t.Fatal(err)
	}
	return path
}

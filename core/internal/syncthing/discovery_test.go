package syncthing

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const testAPIKey = "test-only-api-key"

func TestDiscoverConfigLocationsAndPrecedence(t *testing.T) {
	t.Setenv("STCONFDIR", "")
	t.Setenv("STHOMEDIR", "")
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("XDG_STATE_HOME", "")
	home := t.TempDir()
	current := filepath.Join(home, ".local", "state", "syncthing", "config.xml")
	writeConfig(t, current, "127.0.0.1:8384", false)

	target, err := Discover(context.Background(), DiscoveryOptions{Home: home})
	if err != nil {
		t.Fatal(err)
	}
	if !target.Automatic || target.ConfigPath != current || target.Endpoint != "http://127.0.0.1:8384" {
		t.Fatalf("unexpected automatic target: %#v", target)
	}

	explicit := filepath.Join(home, "explicit.xml")
	writeConfig(t, explicit, "127.0.0.1:9384", false)
	target, err = Discover(context.Background(), DiscoveryOptions{
		ConfigPath: explicit, Endpoint: "http://invalid.example", CredentialFile: "missing",
	})
	if err != nil {
		t.Fatal(err)
	}
	if target.Automatic || target.ConfigPath != explicit || target.Endpoint != "http://127.0.0.1:9384" {
		t.Fatalf("explicit config did not win: %#v", target)
	}
}

func TestDiscoverLegacyAndAmbiguousConfigs(t *testing.T) {
	t.Setenv("STCONFDIR", "")
	t.Setenv("STHOMEDIR", "")
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("XDG_STATE_HOME", "")
	home := t.TempDir()
	legacy := filepath.Join(home, ".local", "share", "syncthing", "config.xml")
	writeConfig(t, legacy, "127.0.0.1:8384", false)
	target, err := Discover(context.Background(), DiscoveryOptions{Home: home,
		SyncthingBinary: filepath.Join(home, "missing-syncthing")})
	if err != nil || target.ConfigPath != legacy {
		t.Fatalf("legacy discovery failed: target=%#v err=%v", target, err)
	}

	writeConfig(t, filepath.Join(home, ".config", "syncthing", "config.xml"),
		"127.0.0.1:8385", false)
	_, err = Discover(context.Background(), DiscoveryOptions{Home: home,
		SyncthingBinary: filepath.Join(home, "missing-syncthing")})
	assertErrorCode(t, err, ErrorAmbiguous)
}

func TestSyncthingPathsDisambiguatesCandidates(t *testing.T) {
	t.Setenv("STCONFDIR", "")
	t.Setenv("STHOMEDIR", "")
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("XDG_STATE_HOME", "")
	home := t.TempDir()
	current := filepath.Join(home, ".local", "state", "syncthing", "config.xml")
	legacy := filepath.Join(home, ".local", "share", "syncthing", "config.xml")
	writeConfig(t, current, "127.0.0.1:8384", false)
	writeConfig(t, legacy, "127.0.0.1:8385", false)
	binary := filepath.Join(t.TempDir(), "syncthing")
	script := "#!/bin/sh\nprintf 'Configuration file:\\n\\t%s\\n' '" + current + "'\n"
	if err := os.WriteFile(binary, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	target, err := Discover(context.Background(), DiscoveryOptions{
		Home: home, SyncthingBinary: binary,
	})
	if err != nil || target.ConfigPath != current {
		t.Fatalf("syncthing paths did not disambiguate: %#v %v", target, err)
	}
}

func TestDiscoverExplicitTargetWithoutSyncthingBinary(t *testing.T) {
	directory := t.TempDir()
	credential := filepath.Join(directory, "credential")
	if err := os.WriteFile(credential, []byte(testAPIKey), 0o600); err != nil {
		t.Fatal(err)
	}
	target, err := Discover(context.Background(), DiscoveryOptions{
		Endpoint: "http://127.0.0.1:8384", CredentialFile: credential,
		SyncthingBinary: filepath.Join(directory, "missing-syncthing"),
	})
	if err != nil {
		t.Fatal(err)
	}
	if target.apiKey != testAPIKey || !target.Local {
		t.Fatalf("unexpected explicit target: %#v", target)
	}
}

func TestDiscoverRejectsUnprotectedCredential(t *testing.T) {
	credential := filepath.Join(t.TempDir(), "credential")
	if err := os.WriteFile(credential, []byte(testAPIKey), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := Discover(context.Background(), DiscoveryOptions{
		Endpoint: "http://127.0.0.1:8384", CredentialFile: credential,
	})
	assertErrorCode(t, err, ErrorCredential)
}

func TestNormalizeEndpoint(t *testing.T) {
	tests := []struct {
		name     string
		value    string
		tls      bool
		endpoint string
		socket   string
		local    bool
	}{
		{"IPv4", "127.0.0.1:8384", false, "http://127.0.0.1:8384", "", true},
		{"IPv6", "[::1]:8384", true, "https://[::1]:8384", "", true},
		{"wildcard IPv4", "0.0.0.0:8384", false, "http://127.0.0.1:8384", "", true},
		{"wildcard IPv6", "[::]:8384", false, "http://[::1]:8384", "", true},
		{"empty wildcard", ":8384", false, "http://127.0.0.1:8384", "", true},
		{"HTTP URL", "http://example.test:8384", false, "http://example.test:8384", "", false},
		{"HTTPS default", "https://example.test", false, "https://example.test:443", "", false},
		{"Unix path", "/run/user/1000/syncthing.sock", false,
			"unix:///run/user/1000/syncthing.sock", "/run/user/1000/syncthing.sock", true},
		{"Unix URL", "unix:///tmp/syncthing.sock", false,
			"unix:///tmp/syncthing.sock", "/tmp/syncthing.sock", true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			endpoint, socket, local, err := normalizeEndpoint(test.value, test.tls)
			if err != nil {
				t.Fatal(err)
			}
			if endpoint != test.endpoint || socket != test.socket || local != test.local {
				t.Fatalf("got (%q, %q, %v), want (%q, %q, %v)",
					endpoint, socket, local, test.endpoint, test.socket, test.local)
			}
		})
	}
}

func TestConfigDoesNotExposeCredential(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.xml")
	writeConfig(t, path, "127.0.0.1:8384", false)
	target, err := targetFromConfig(path, "")
	if err != nil {
		t.Fatal(err)
	}
	client, err := NewClient(target)
	if err != nil {
		t.Fatal(err)
	}
	if public := fmt.Sprintf("%#v %#v", client.Target(), *client); containsSecret(public) {
		t.Fatal("public target or formatted client exposed the credential")
	}
}

func FuzzConfigXML(f *testing.F) {
	f.Add([]byte(`<configuration><gui tls="false"><address>127.0.0.1:8384</address><apikey>x</apikey></gui></configuration>`))
	f.Add([]byte(`<configuration>`))
	f.Fuzz(func(t *testing.T, contents []byte) {
		_, _ = parseConfig(contents)
	})
}

func assertErrorCode(t *testing.T, err error, code ErrorCode) {
	t.Helper()
	var target *Error
	if !errors.As(err, &target) || target.Code != code {
		t.Fatalf("got error %v, want code %s", err, code)
	}
}

func writeConfig(t *testing.T, path, address string, tls bool) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	contents := fmt.Sprintf(`<configuration><gui tls="%t"><address>%s</address><apikey>%s</apikey></gui></configuration>`,
		tls, address, testAPIKey)
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
}

func containsSecret(value string) bool {
	return strings.Contains(value, testAPIKey)
}

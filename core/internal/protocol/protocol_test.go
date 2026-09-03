package protocol

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/omarchy-QOL/syncshell/core/internal/session"
	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
)

const protocolTestKey = "protocol-test-key"

func TestStreamShutdownContract(t *testing.T) {
	coreSession, _ := newProtocolSession(t, false)
	input := strings.NewReader(`{"v":1,"type":"shutdown","id":"10"}` + "\n")
	var output bytes.Buffer
	err := (Stream{Session: coreSession, Input: input, Output: &output,
		Build: Build{Version: "0.1.8", Protocol: Version, GoVersion: "test"}}).Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	frames := decodeFrames(t, output.Bytes())
	assertTypes(t, frames, "hello", "snapshot", "result", "end")
	if frames[2]["id"] != "10" || frames[2]["ok"] != true || frames[3]["reason"] != "shutdown" {
		t.Fatalf("unexpected shutdown frames: %#v", frames)
	}
}

func TestStreamConfigureRefreshAndRescan(t *testing.T) {
	coreSession, rescans := newProtocolSession(t, false)
	input := strings.NewReader(
		`{"v":1,"type":"configure","id":"1","config":{"probeIntervalSeconds":2}}` + "\n" +
			`{"v":1,"type":"refresh","id":"2"}` + "\n" +
			`{"v":1,"type":"action","id":"3","action":"folder.rescan","args":{"folderId":"folder"}}` + "\n" +
			`{"v":1,"type":"shutdown","id":"4"}` + "\n")
	var output bytes.Buffer
	err := (Stream{Session: coreSession, Input: input, Output: &output,
		Build: Build{Version: "0.1.8", Protocol: Version}}).Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if rescans.Load() != 1 {
		t.Fatalf("got %d rescans, want 1", rescans.Load())
	}
	if coreSession.ProbeInterval().Seconds() != 2 {
		t.Fatalf("configure did not update interval: %v", coreSession.ProbeInterval())
	}
	frames := decodeFrames(t, output.Bytes())
	results := make(map[string]map[string]any)
	for _, frame := range frames {
		if frame["type"] == "result" {
			results[frame["id"].(string)] = frame
		}
	}
	for _, id := range []string{"1", "2", "3", "4"} {
		if results[id] == nil || results[id]["ok"] != true {
			t.Fatalf("missing successful result %s: %#v", id, results)
		}
	}
}

func TestStreamRejectsMalformedDuplicateAndWrongVersion(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"malformed", "{\n"},
		{"duplicate", `{"v":1,"type":"refresh","id":"1"}` + "\n" +
			`{"v":1,"type":"refresh","id":"1"}` + "\n"},
		{"wrong version", `{"v":2,"type":"refresh","id":"1"}` + "\n"},
		{"unknown field", `{"v":1,"type":"refresh","id":"1","unknown":true}` + "\n"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			coreSession, _ := newProtocolSession(t, false)
			var output bytes.Buffer
			err := (Stream{Session: coreSession, Input: strings.NewReader(test.input),
				Output: &output, Build: Build{Version: "0.1.8", Protocol: Version}}).
				Run(context.Background())
			if err == nil {
				t.Fatal("invalid protocol input succeeded")
			}
			frames := decodeFrames(t, output.Bytes())
			if frames[len(frames)-1]["type"] != "fatal" {
				t.Fatalf("last frame is not fatal: %#v", frames)
			}
		})
	}
}

func TestStreamBoundsInputAndEndsOnClosedStdin(t *testing.T) {
	coreSession, _ := newProtocolSession(t, false)
	var output bytes.Buffer
	err := (Stream{Session: coreSession,
		Input: bytes.NewReader(bytes.Repeat([]byte{'x'}, MaxLineBytes)), Output: &output,
		Build: Build{Version: "0.1.8", Protocol: Version}}).Run(context.Background())
	if err == nil {
		t.Fatal("oversized line succeeded")
	}
	frames := decodeFrames(t, output.Bytes())
	if frames[len(frames)-1]["code"] != "line_too_large" {
		t.Fatalf("unexpected oversized result: %#v", frames[len(frames)-1])
	}

	coreSession, _ = newProtocolSession(t, false)
	output.Reset()
	err = (Stream{Session: coreSession, Input: strings.NewReader(""), Output: &output,
		Build: Build{Version: "0.1.8", Protocol: Version}}).Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	frames = decodeFrames(t, output.Bytes())
	assertTypes(t, frames, "hello", "snapshot", "end")
	if frames[2]["reason"] != "stdin" {
		t.Fatalf("unexpected end frame: %#v", frames[2])
	}
}

func TestStreamStdoutIsJSONAndSecretFree(t *testing.T) {
	coreSession, _ := newProtocolSession(t, true)
	var output bytes.Buffer
	if err := (Stream{Session: coreSession, Input: strings.NewReader(""), Output: &output,
		Build: Build{Version: "0.1.8", Protocol: Version}}).Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(output.String(), protocolTestKey) {
		t.Fatal("protocol output exposed the API key")
	}
	scanner := bufio.NewScanner(bytes.NewReader(output.Bytes()))
	for scanner.Scan() {
		if !json.Valid(scanner.Bytes()) {
			t.Fatalf("stdout contains a non-JSON line: %q", scanner.Bytes())
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
}

func FuzzRequestDecoder(f *testing.F) {
	f.Add([]byte(`{"v":1,"type":"refresh","id":"1"}`))
	f.Add([]byte(`{`))
	f.Fuzz(func(t *testing.T, data []byte) {
		var request request
		_ = decodeStrict(data, &request)
	})
}

func newProtocolSession(t *testing.T, unauthorized bool) (*session.Session, *atomic.Int32) {
	t.Helper()
	var rescans atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/rest/noauth/health" && unauthorized {
			http.Error(writer, "secret "+protocolTestKey, http.StatusUnauthorized)
			return
		}
		switch request.URL.Path {
		case "/rest/noauth/health":
			protocolJSON(writer, `{"status":"OK"}`)
		case "/rest/system/status":
			protocolJSON(writer, `{"myID":"LOCAL-ID"}`)
		case "/rest/system/version":
			protocolJSON(writer, `{"version":"v2.1.3"}`)
		case "/rest/config/devices":
			protocolJSON(writer, `[]`)
		case "/rest/config/folders":
			protocolJSON(writer,
				`[{"id":"folder","label":"Folder","path":"/tmp/folder","paused":false}]`)
		case "/rest/system/connections":
			protocolJSON(writer, `{"connections":{}}`)
		case "/rest/db/status":
			protocolJSON(writer, `{"state":"idle"}`)
		case "/rest/db/scan":
			rescans.Add(1)
			writer.WriteHeader(http.StatusOK)
		default:
			http.NotFound(writer, request)
		}
	}))
	t.Cleanup(server.Close)
	configPath := filepath.Join(t.TempDir(), "config.xml")
	config := fmt.Sprintf(`<configuration><gui tls="false"><address>%s</address><apikey>%s</apikey></gui></configuration>`,
		strings.TrimPrefix(server.URL, "http://"), protocolTestKey)
	if err := os.WriteFile(configPath, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	coreSession, err := session.New(context.Background(), session.Config{
		Discovery: syncthing.DiscoveryOptions{ConfigPath: configPath},
	})
	if err != nil {
		t.Fatal(err)
	}
	return coreSession, &rescans
}

func decodeFrames(t *testing.T, output []byte) []map[string]any {
	t.Helper()
	var frames []map[string]any
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		var frame map[string]any
		if err := json.Unmarshal(scanner.Bytes(), &frame); err != nil {
			t.Fatalf("invalid frame %q: %v", scanner.Bytes(), err)
		}
		frames = append(frames, frame)
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	return frames
}

func assertTypes(t *testing.T, frames []map[string]any, expected ...string) {
	t.Helper()
	if len(frames) != len(expected) {
		t.Fatalf("got %d frames, want %d: %#v", len(frames), len(expected), frames)
	}
	for index, frameType := range expected {
		if frames[index]["type"] != frameType {
			t.Fatalf("frame %d type=%v, want %s", index, frames[index]["type"], frameType)
		}
	}
}

func protocolJSON(writer http.ResponseWriter, value string) {
	writer.Header().Set("Content-Type", "application/json")
	_, _ = writer.Write([]byte(value))
}

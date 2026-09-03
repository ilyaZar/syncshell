package syncthing

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

func TestClientHealthStatusFoldersAndRescan(t *testing.T) {
	var rescans atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/rest/noauth/health" && request.Header.Get("X-API-Key") != testAPIKey {
			http.Error(writer, "unauthorized", http.StatusUnauthorized)
			return
		}
		switch request.URL.Path {
		case "/rest/noauth/health":
			writeJSON(writer, `{"status":"OK"}`)
		case "/rest/system/status":
			writeJSON(writer, `{"myID":"LOCAL-ID"}`)
		case "/rest/system/version":
			writeJSON(writer, `{"version":"v2.1.3"}`)
		case "/rest/config/devices":
			writeJSON(writer, `[{"deviceID":"LOCAL-ID","name":"local"}]`)
		case "/rest/config/folders":
			writeJSON(writer, `[{"id":"folder","label":"Folder","path":"/tmp/folder","paused":false}]`)
		case "/rest/system/connections":
			writeJSON(writer, `{"connections":{}}`)
		case "/rest/db/status":
			writeJSON(writer, `{"state":"idle","globalFiles":2,"globalBytes":9}`)
		case "/rest/db/scan":
			if request.Method != http.MethodPost || request.URL.Query().Get("folder") != "folder" {
				http.Error(writer, "bad scan", http.StatusBadRequest)
				return
			}
			rescans.Add(1)
			writer.WriteHeader(http.StatusOK)
		default:
			http.NotFound(writer, request)
		}
	}))
	defer server.Close()

	client := testClient(t, server.URL, "", false)
	ctx := context.Background()
	if err := client.Health(ctx); err != nil {
		t.Fatal(err)
	}
	status, err := client.Status(ctx)
	if err != nil || status.MyID != "LOCAL-ID" {
		t.Fatalf("unexpected status: %#v %v", status, err)
	}
	folders, err := client.Folders(ctx)
	if err != nil || len(folders) != 1 || folders[0].ID != "folder" {
		t.Fatalf("unexpected folders: %#v %v", folders, err)
	}
	if err := client.Rescan(ctx, "folder"); err != nil {
		t.Fatal(err)
	}
	if rescans.Load() != 1 {
		t.Fatalf("got %d rescans, want 1", rescans.Load())
	}
}

func TestRescanConfirmsLongRunningScanAfterTimeout(t *testing.T) {
	tests := []struct {
		name     string
		folderID string
		state    string
		wantOK   bool
	}{
		{name: "folder scanning", folderID: "folder", state: "scanning", wantOK: true},
		{name: "global scan waiting", state: "scan-waiting", wantOK: true},
		{name: "folder idle", folderID: "folder", state: "idle", wantOK: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var started atomic.Bool
			server := httptest.NewServer(http.HandlerFunc(func(
				writer http.ResponseWriter,
				request *http.Request,
			) {
				switch request.URL.Path {
				case "/rest/db/scan":
					started.Store(true)
					<-request.Context().Done()
				case "/rest/config/folders":
					writeJSON(writer, `[{"id":"folder","paused":false}]`)
				case "/rest/db/status":
					if !started.Load() {
						t.Fatal("folder status read before rescan started")
					}
					writeJSON(writer, `{"state":"`+test.state+`"}`)
				default:
					http.NotFound(writer, request)
				}
			}))
			defer server.Close()

			client := testClient(t, server.URL, "", false)
			client.http.Timeout = 50 * time.Millisecond
			err := client.Rescan(context.Background(), test.folderID)
			if test.wantOK {
				if err != nil {
					t.Fatalf("confirmed rescan failed: %v", err)
				}
				return
			}
			assertErrorCode(t, err, ErrorTimeout)
		})
	}
}

func TestClientAuthorizationAndSecretRedaction(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		http.Error(writer, "rejected "+testAPIKey, http.StatusUnauthorized)
	}))
	defer server.Close()
	client := testClient(t, server.URL, "", false)
	_, err := client.Status(context.Background())
	assertErrorCode(t, err, ErrorUnauthorized)
	if containsSecret(err.Error()) {
		t.Fatal("authorization error exposed the credential")
	}
}

func TestClientRejectsCrossOriginRedirectWithoutCredentialLeak(t *testing.T) {
	var leaked atomic.Bool
	destination := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		leaked.Store(request.Header.Get("X-API-Key") != "")
		writeJSON(writer, `{"myID":"WRONG"}`)
	}))
	defer destination.Close()
	source := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		http.Redirect(writer, request, destination.URL, http.StatusTemporaryRedirect)
	}))
	defer source.Close()
	client := testClient(t, source.URL, "", false)
	_, err := client.Status(context.Background())
	if err == nil {
		t.Fatal("cross-origin redirect succeeded")
	}
	if leaked.Load() {
		t.Fatal("credential crossed an origin boundary")
	}
}

func TestClientTimeoutAndCancellation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		<-request.Context().Done()
		writer.WriteHeader(http.StatusGatewayTimeout)
	}))
	defer server.Close()
	client := testClient(t, server.URL, "", false)
	client.http.Timeout = 50 * time.Millisecond
	_, err := client.Status(context.Background())
	assertErrorCode(t, err, ErrorTimeout)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err = client.Status(ctx)
	assertErrorCode(t, err, ErrorCanceled)
}

func TestClientPinnedHTTPS(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.Header.Get("X-API-Key") != testAPIKey {
			http.Error(writer, "unauthorized", http.StatusUnauthorized)
			return
		}
		writeJSON(writer, `{"myID":"TLS-ID"}`)
	}))
	defer server.Close()
	certificate := filepath.Join(t.TempDir(), "https-cert.pem")
	block := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw})
	if err := os.WriteFile(certificate, block, 0o600); err != nil {
		t.Fatal(err)
	}
	client := testClient(t, server.URL, certificate, false)
	status, err := client.Status(context.Background())
	if err != nil || status.MyID != "TLS-ID" {
		t.Fatalf("pinned TLS failed: %#v %v", status, err)
	}

	if err := os.WriteFile(certificate, unrelatedCertificate(t), 0o600); err != nil {
		t.Fatal(err)
	}
	bad := testClient(t, server.URL, certificate, false)
	_, err = bad.Status(context.Background())
	assertErrorCode(t, err, ErrorTLS)
}

func TestClientExplicitInsecureHTTPS(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, `{"myID":"INSECURE-ID"}`)
	}))
	defer server.Close()
	client := testClient(t, server.URL, "", true)
	status, err := client.Status(context.Background())
	if err != nil || status.MyID != "INSECURE-ID" {
		t.Fatalf("explicit insecure TLS failed: %#v %v", status, err)
	}
}

func TestClientIPv6(t *testing.T) {
	listener, err := net.Listen("tcp6", "[::1]:0")
	if err != nil {
		t.Skipf("IPv6 loopback unavailable: %v", err)
	}
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		writeJSON(writer, `{"myID":"IPV6-ID"}`)
	}))
	server.Listener = listener
	server.Start()
	defer server.Close()
	client := testClient(t, server.URL, "", false)
	status, err := client.Status(context.Background())
	if err != nil || status.MyID != "IPV6-ID" {
		t.Fatalf("IPv6 target failed: %#v %v", status, err)
	}
}

func TestClientBoundsResponseBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, _ *http.Request) {
		_, _ = writer.Write(bytes.Repeat([]byte{'x'}, maxResponseBytes+1))
	}))
	defer server.Close()
	client := testClient(t, server.URL, "", false)
	_, err := client.Status(context.Background())
	assertErrorCode(t, err, ErrorSchema)
}

func TestClientUnixSocket(t *testing.T) {
	socket := filepath.Join(t.TempDir(), "syncthing.sock")
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/rest/noauth/health" {
			writeJSON(writer, `{"status":"OK"}`)
			return
		}
		writeJSON(writer, `{"myID":"UNIX-ID"}`)
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Shutdown(context.Background()) })
	client, err := NewClient(Target{Endpoint: "unix://" + socket,
		unixSocket: socket, apiKey: testAPIKey, Local: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Health(context.Background()); err != nil {
		t.Fatal(err)
	}
	status, err := client.Status(context.Background())
	if err != nil || status.MyID != "UNIX-ID" {
		t.Fatalf("unexpected Unix status: %#v %v", status, err)
	}
}

func TestClientEventsUsesBoundedFilteredCursor(t *testing.T) {
	var query url.Values
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		query = request.URL.Query()
		if request.Header.Get("X-API-Key") != testAPIKey {
			http.Error(writer, "unauthorized", http.StatusUnauthorized)
			return
		}
		writeJSON(writer, `[{"id":7,"type":"ConfigSaved","data":{}}]`)
	}))
	defer server.Close()
	client := testClient(t, server.URL, "", false)
	events, err := client.Events(context.Background(), 6, 32, 1,
		[]string{"ConfigSaved", "FolderSummary"})
	if err != nil || len(events) != 1 || events[0].ID != 7 {
		t.Fatalf("unexpected events: %#v %v", events, err)
	}
	if query.Get("since") != "6" || query.Get("limit") != "32" ||
		query.Get("timeout") != "1" || query.Get("events") != "ConfigSaved,FolderSummary" {
		t.Fatalf("unexpected event query: %v", query)
	}
}

func FuzzEndpointNormalization(f *testing.F) {
	f.Add("127.0.0.1:8384", false)
	f.Add("unix:///tmp/syncthing.sock", false)
	f.Fuzz(func(t *testing.T, value string, tlsEnabled bool) {
		_, _, _, _ = normalizeEndpoint(value, tlsEnabled)
	})
}

func testClient(t *testing.T, endpoint, certificate string, insecure bool) *Client {
	t.Helper()
	normalized, socket, local, err := normalizeEndpoint(endpoint, false)
	if err != nil {
		t.Fatal(err)
	}
	client, err := NewClient(Target{Endpoint: normalized, unixSocket: socket,
		Local: local, apiKey: testAPIKey, tlsCertificate: certificate,
		insecureTLS: insecure})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func writeJSON(writer http.ResponseWriter, body string) {
	writer.Header().Set("Content-Type", "application/json")
	_, _ = writer.Write([]byte(body))
}

func unrelatedCertificate(t *testing.T) []byte {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	template := x509.Certificate{SerialNumber: big.NewInt(99),
		Subject:   pkix.Name{CommonName: "unrelated"},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
}

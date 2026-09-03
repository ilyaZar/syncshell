package syncthing

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const maxResponseBytes = 8 << 20

// Client owns authenticated transport to one selected Syncthing instance.
type Client struct {
	target    Target
	http      *http.Client
	eventHTTP *http.Client
	base      string
}

// String returns only nonsecret client identity.
func (c Client) String() string { return c.target.String() }

// GoString prevents diagnostic formatting from exposing private fields.
func (c Client) GoString() string { return c.String() }

// NewClient builds one bounded transport without exposing the API key.
func NewClient(target Target) (*Client, error) {
	dialer := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 30 * time.Second}
	transport := &http.Transport{
		Proxy:                 nil,
		DialContext:           dialer.DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          4,
		MaxIdleConnsPerHost:   2,
		IdleConnTimeout:       45 * time.Second,
		TLSHandshakeTimeout:   4 * time.Second,
		ResponseHeaderTimeout: 8 * time.Second,
	}
	base := target.Endpoint
	if target.unixSocket != "" {
		network := "unix"
		transport.DialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
			return dialer.DialContext(ctx, network, target.unixSocket)
		}
		if strings.HasPrefix(target.Endpoint, "unixs://") {
			base = "https://unix"
		} else {
			base = "http://unix"
		}
	}
	tlsConfig, err := targetTLSConfig(target)
	if err != nil {
		return nil, err
	}
	transport.TLSClientConfig = tlsConfig

	origin, err := url.Parse(base)
	if err != nil {
		return nil, failure(ErrorConfig, "client", "Syncthing endpoint is invalid", err)
	}
	checkRedirect := func(request *http.Request, via []*http.Request) error {
		if request.URL.Scheme != origin.Scheme || request.URL.Host != origin.Host {
			return errors.New("cross-origin redirect rejected")
		}
		if len(via) >= 3 {
			return errors.New("redirect limit exceeded")
		}
		return nil
	}
	client := &http.Client{
		Transport:     transport,
		Timeout:       15 * time.Second,
		CheckRedirect: checkRedirect,
	}
	eventClient := &http.Client{Transport: transport, Timeout: 70 * time.Second,
		CheckRedirect: checkRedirect}
	return &Client{target: target, http: client, eventHTTP: eventClient,
		base: strings.TrimRight(base, "/")}, nil
}

func targetTLSConfig(target Target) (*tls.Config, error) {
	if !strings.HasPrefix(target.Endpoint, "https://") &&
		!strings.HasPrefix(target.Endpoint, "unixs://") {
		return nil, nil
	}
	if target.insecureTLS {
		// Explicit insecure mode is limited to the selected target.
		return &tls.Config{InsecureSkipVerify: true, MinVersion: tls.VersionTLS12}, nil
	}
	if target.tlsCertificate == "" {
		return &tls.Config{MinVersion: tls.VersionTLS12}, nil
	}
	contents, err := os.ReadFile(target.tlsCertificate)
	if err != nil {
		return nil, failure(ErrorTLS, "tls", "could not read TLS certificate", err)
	}
	block, _ := pem.Decode(contents)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, failure(ErrorTLS, "tls", "TLS certificate is invalid", nil)
	}
	certificate, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, failure(ErrorTLS, "tls", "TLS certificate is invalid", err)
	}
	expected := sha256.Sum256(certificate.Raw)
	return &tls.Config{
		// Certificate pinning below replaces public-PKI hostname verification.
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
		VerifyConnection: func(state tls.ConnectionState) error {
			if len(state.PeerCertificates) == 0 {
				return errors.New("peer certificate missing")
			}
			actual := sha256.Sum256(state.PeerCertificates[0].Raw)
			if subtle.ConstantTimeCompare(actual[:], expected[:]) != 1 {
				return errors.New("peer certificate mismatch")
			}
			now := time.Now()
			if now.Before(certificate.NotBefore) || now.After(certificate.NotAfter) {
				return errors.New("peer certificate is outside its validity period")
			}
			return nil
		},
	}, nil
}

// Endpoint returns the sanitized selected target.
func (c *Client) Endpoint() string { return c.target.Endpoint }

// Target returns the selected nonsecret target metadata.
func (c *Client) Target() Target {
	target := c.target
	target.apiKey = ""
	target.tlsCertificate = ""
	target.unixSocket = ""
	return target
}

// Health probes transport without attaching a credential.
func (c *Client) Health(ctx context.Context) error {
	var response struct {
		Status string `json:"status"`
	}
	if err := c.request(ctx, http.MethodGet, "/rest/noauth/health", nil, false, &response); err != nil {
		return err
	}
	if response.Status != "OK" {
		return failure(ErrorSchema, "health", "Syncthing health response is invalid", nil)
	}
	return nil
}

// Status reads authenticated instance identity.
func (c *Client) Status(ctx context.Context) (SystemStatus, error) {
	var response SystemStatus
	err := c.request(ctx, http.MethodGet, "/rest/system/status", nil, true, &response)
	if err == nil && strings.TrimSpace(response.MyID) == "" {
		err = failure(ErrorSchema, "status", "Syncthing identity is missing", nil)
	}
	return response, err
}

// Version reads the selected Syncthing version.
func (c *Client) Version(ctx context.Context) (SystemVersion, error) {
	var response SystemVersion
	err := c.request(ctx, http.MethodGet, "/rest/system/version", nil, true, &response)
	return response, err
}

// Devices reads configured devices.
func (c *Client) Devices(ctx context.Context) ([]Device, error) {
	var response []Device
	err := c.request(ctx, http.MethodGet, "/rest/config/devices", nil, true, &response)
	return response, err
}

// Folders reads configured folders.
func (c *Client) Folders(ctx context.Context) ([]Folder, error) {
	var response []Folder
	err := c.request(ctx, http.MethodGet, "/rest/config/folders", nil, true, &response)
	return response, err
}

// Connections reads configured peer connectivity.
func (c *Client) Connections(ctx context.Context) (Connections, error) {
	var response Connections
	err := c.request(ctx, http.MethodGet, "/rest/system/connections", nil, true, &response)
	return response, err
}

// FolderStatus reads one folder's authoritative database state.
func (c *Client) FolderStatus(ctx context.Context, folderID string) (FolderStatus, error) {
	var response FolderStatus
	path := "/rest/db/status?folder=" + url.QueryEscape(folderID)
	err := c.request(ctx, http.MethodGet, path, nil, true, &response)
	return response, err
}

// Rescan requests one verified folder scan.
func (c *Client) Rescan(ctx context.Context, folderID string) error {
	path := "/rest/db/scan"
	if folderID != "" {
		path += "?folder=" + url.QueryEscape(folderID)
	}
	return c.request(ctx, http.MethodPost, path, nil, true, nil)
}

func (c *Client) request(
	ctx context.Context,
	method string,
	path string,
	body []byte,
	authenticated bool,
	destination any,
) error {
	return c.requestWith(c.http, ctx, method, path, body, authenticated, destination)
}

func (c *Client) requestWith(
	httpClient *http.Client,
	ctx context.Context,
	method string,
	path string,
	body []byte,
	authenticated bool,
	destination any,
	acceptedStatuses ...int,
) error {
	request, err := http.NewRequestWithContext(ctx, method, c.base+path, bytes.NewReader(body))
	if err != nil {
		return failure(ErrorConfig, "request", "could not create Syncthing request", err)
	}
	request.Header.Set("Accept", "application/json")
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	if authenticated {
		request.Header.Set("X-API-Key", c.target.apiKey)
	}
	response, err := httpClient.Do(request)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "tls") ||
			strings.Contains(strings.ToLower(err.Error()), "certificate") {
			return failure(ErrorTLS, "request", "Syncthing TLS verification failed", err)
		}
		return classifyNetwork("request", err)
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return failure(ErrorUnauthorized, "request", "Syncthing authorization failed", nil)
	}
	accepted := false
	for _, status := range acceptedStatuses {
		if response.StatusCode == status {
			accepted = true
			break
		}
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		if accepted {
			return nil
		}
		return failure(ErrorHTTP, "request",
			fmt.Sprintf("Syncthing returned HTTP %d", response.StatusCode), nil)
	}
	contents, err := io.ReadAll(io.LimitReader(response.Body, maxResponseBytes+1))
	if err != nil {
		return classifyNetwork("response", err)
	}
	if len(contents) > maxResponseBytes {
		return failure(ErrorSchema, "response", "Syncthing response is too large", nil)
	}
	if destination == nil {
		return nil
	}
	decoder := json.NewDecoder(bytes.NewReader(contents))
	if err := decoder.Decode(destination); err != nil {
		return failure(ErrorSchema, "request", "Syncthing response is invalid", err)
	}
	var extra json.RawMessage
	if err := decoder.Decode(&extra); err != io.EOF {
		return failure(ErrorSchema, "request", "Syncthing response contains trailing data", err)
	}
	return nil
}

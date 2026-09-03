package syncthing

import (
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	maxConfigBytes     = 1 << 20
	maxCredentialBytes = 4096
	maxPathsOutput     = 64 << 10
)

// DiscoveryOptions selects exactly one Syncthing target.
type DiscoveryOptions struct {
	ConfigPath       string
	Endpoint         string
	CredentialFile   string
	TLSCertificate   string
	ExpectedDeviceID string
	InsecureTLS      bool

	Home            string
	ConfigHome      string
	StateHome       string
	SyncthingBinary string
}

// Target is the selected endpoint. Its API key is deliberately private.
type Target struct {
	Endpoint         string
	ConfigPath       string
	ExpectedDeviceID string
	Local            bool
	Automatic        bool

	apiKey         string
	unixSocket     string
	tlsCertificate string
	insecureTLS    bool
}

// String returns only nonsecret target identity.
func (t Target) String() string {
	return fmt.Sprintf("Target{Endpoint:%q ConfigPath:%q Local:%t Automatic:%t}",
		t.Endpoint, t.ConfigPath, t.Local, t.Automatic)
}

// GoString prevents diagnostic formatting from exposing private fields.
func (t Target) GoString() string { return t.String() }

type configXML struct {
	GUI struct {
		TLS     bool   `xml:"tls,attr"`
		Address string `xml:"address"`
		APIKey  string `xml:"apikey"`
	} `xml:"gui"`
}

// Discover applies the documented explicit-config, explicit-target, then
// unambiguous-local precedence.
func Discover(ctx context.Context, options DiscoveryOptions) (Target, error) {
	if options.ConfigPath != "" {
		return targetFromConfig(options.ConfigPath, options.ExpectedDeviceID)
	}
	if options.Endpoint != "" {
		return targetFromExplicit(options)
	}

	paths := existingConfigPaths(candidateConfigPaths(options))
	if len(paths) != 1 {
		if commandPath, err := syncthingConfigPath(ctx, options); err == nil {
			if regularFile(commandPath) {
				paths = []string{commandPath}
			}
		}
	}
	if len(paths) == 0 {
		return Target{}, failure(ErrorConfig, "discover",
			"Syncthing configuration was not found", nil)
	}
	if len(paths) != 1 {
		return Target{}, failure(ErrorAmbiguous, "discover",
			"multiple Syncthing configurations were found", nil)
	}
	target, err := targetFromConfig(paths[0], options.ExpectedDeviceID)
	if err != nil {
		return Target{}, err
	}
	target.Automatic = true
	return target, nil
}

func targetFromConfig(path, expectedDeviceID string) (Target, error) {
	cleanPath, err := filepath.Abs(path)
	if err != nil {
		return Target{}, failure(ErrorConfig, "config", "invalid configuration path", err)
	}
	file, err := os.Open(cleanPath)
	if err != nil {
		return Target{}, failure(ErrorConfig, "config", "could not read Syncthing configuration", err)
	}
	defer file.Close()

	contents, err := io.ReadAll(io.LimitReader(file, maxConfigBytes+1))
	if err != nil || len(contents) > maxConfigBytes {
		return Target{}, failure(ErrorConfig, "config",
			"Syncthing configuration is too large", err)
	}
	config, err := parseConfig(contents)
	if err != nil {
		return Target{}, failure(ErrorConfig, "config", "Syncthing configuration is malformed", err)
	}
	apiKey := strings.TrimSpace(config.GUI.APIKey)
	if apiKey == "" || strings.ContainsAny(apiKey, "\r\n\x00") {
		return Target{}, failure(ErrorCredential, "config", "Syncthing API credential is missing", nil)
	}
	endpoint, socket, local, err := normalizeEndpoint(config.GUI.Address, config.GUI.TLS)
	if err != nil {
		return Target{}, err
	}
	target := Target{
		Endpoint:         endpoint,
		ConfigPath:       cleanPath,
		ExpectedDeviceID: strings.TrimSpace(expectedDeviceID),
		Local:            local,
		apiKey:           apiKey,
		unixSocket:       socket,
	}
	if strings.HasPrefix(endpoint, "https://") || strings.HasPrefix(endpoint, "unixs://") {
		certificate := filepath.Join(filepath.Dir(cleanPath), "https-cert.pem")
		if !regularFile(certificate) {
			return Target{}, failure(ErrorTLS, "config",
				"local HTTPS certificate was not found", nil)
		}
		target.tlsCertificate = certificate
	}
	return target, nil
}

func parseConfig(contents []byte) (configXML, error) {
	var config configXML
	if err := xml.Unmarshal(contents, &config); err != nil {
		return configXML{}, err
	}
	return config, nil
}

func targetFromExplicit(options DiscoveryOptions) (Target, error) {
	if options.CredentialFile == "" {
		return Target{}, failure(ErrorCredential, "discover",
			"an explicit target requires a protected credential file", nil)
	}
	apiKey, err := readProtectedCredential(options.CredentialFile)
	if err != nil {
		return Target{}, err
	}
	endpoint, socket, local, err := normalizeEndpoint(options.Endpoint, false)
	if err != nil {
		return Target{}, err
	}
	if options.InsecureTLS && !strings.HasPrefix(endpoint, "https://") &&
		!strings.HasPrefix(endpoint, "unixs://") {
		return Target{}, failure(ErrorTLS, "discover",
			"insecure TLS is valid only for an HTTPS target", nil)
	}
	certificate := ""
	if options.TLSCertificate != "" {
		certificate, err = filepath.Abs(options.TLSCertificate)
		if err != nil || !regularFile(certificate) {
			return Target{}, failure(ErrorTLS, "discover",
				"TLS certificate was not found", err)
		}
	}
	return Target{
		Endpoint:         endpoint,
		ExpectedDeviceID: strings.TrimSpace(options.ExpectedDeviceID),
		Local:            local,
		apiKey:           apiKey,
		unixSocket:       socket,
		tlsCertificate:   certificate,
		insecureTLS:      options.InsecureTLS,
	}, nil
}

func readProtectedCredential(path string) (string, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o077 != 0 {
		return "", failure(ErrorCredential, "credential",
			"credential file must be a private regular file", err)
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return "", failure(ErrorCredential, "credential",
			"could not read credential file", err)
	}
	if len(contents) > maxCredentialBytes {
		return "", failure(ErrorCredential, "credential",
			"credential file is too large", nil)
	}
	credential := strings.TrimSpace(string(contents))
	if credential == "" || strings.ContainsAny(credential, "\r\n\x00") {
		return "", failure(ErrorCredential, "credential",
			"credential file is invalid", nil)
	}
	return credential, nil
}

func candidateConfigPaths(options DiscoveryOptions) []string {
	home := options.Home
	if home == "" {
		home, _ = os.UserHomeDir()
	}
	configHome := options.ConfigHome
	if configHome == "" {
		configHome = os.Getenv("XDG_CONFIG_HOME")
	}
	if configHome == "" && home != "" {
		configHome = filepath.Join(home, ".config")
	}
	stateHome := options.StateHome
	if stateHome == "" {
		stateHome = os.Getenv("XDG_STATE_HOME")
	}
	if stateHome == "" && home != "" {
		stateHome = filepath.Join(home, ".local", "state")
	}

	paths := make([]string, 0, 7)
	if value := os.Getenv("STCONFDIR"); value != "" {
		paths = append(paths, filepath.Join(value, "config.xml"))
	}
	if value := os.Getenv("STHOMEDIR"); value != "" {
		paths = append(paths, filepath.Join(value, "config.xml"))
	}
	paths = append(paths,
		filepath.Join(stateHome, "syncthing", "config.xml"),
		filepath.Join(configHome, "syncthing", "config.xml"),
		filepath.Join(home, ".local", "share", "syncthing", "config.xml"),
	)
	return deduplicatePaths(paths)
}

func existingConfigPaths(paths []string) []string {
	existing := make([]string, 0, len(paths))
	for _, path := range paths {
		if regularFile(path) {
			existing = append(existing, path)
		}
	}
	return existing
}

func deduplicatePaths(paths []string) []string {
	seen := make(map[string]struct{}, len(paths))
	result := make([]string, 0, len(paths))
	for _, path := range paths {
		if path == "" {
			continue
		}
		clean := filepath.Clean(path)
		if _, ok := seen[clean]; ok {
			continue
		}
		seen[clean] = struct{}{}
		result = append(result, clean)
	}
	return result
}

func regularFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func syncthingConfigPath(ctx context.Context, options DiscoveryOptions) (string, error) {
	binary := options.SyncthingBinary
	if binary == "" {
		var err error
		binary, err = exec.LookPath("syncthing")
		if err != nil {
			return "", err
		}
	}
	commandContext, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	command := exec.CommandContext(commandContext, binary, "paths")
	output, err := command.Output()
	if err != nil || len(output) > maxPathsOutput {
		return "", errors.New("syncthing paths failed")
	}
	lines := strings.Split(string(output), "\n")
	for index, line := range lines {
		if strings.TrimSpace(line) != "Configuration file:" || index+1 >= len(lines) {
			continue
		}
		path := strings.TrimSpace(lines[index+1])
		if path == "" {
			break
		}
		return filepath.Clean(path), nil
	}
	return "", fmt.Errorf("configuration path missing")
}

package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/protocol"
	"github.com/omarchy-QOL/syncshell/core/internal/session"
	"github.com/omarchy-QOL/syncshell/core/internal/systemduser"
)

var buildVersion = "0.1.8"

func main() {
	if err := run(context.Background(), os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "syncshell-core:", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, args []string, stdin io.Reader, stdout io.Writer) error {
	if len(args) == 0 {
		return errors.New("expected probe, status, or stream")
	}
	command := args[0]
	if command != "probe" && command != "status" && command != "stream" {
		return errors.New("expected probe, status, or stream")
	}
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	options, outputJSON, err := parseOptions(flags, args[1:])
	if err != nil {
		return err
	}
	if command != "stream" && !outputJSON {
		return errors.New("probe and status require --json")
	}

	coreSession, err := session.New(ctx, options)
	if err != nil {
		return err
	}
	switch command {
	case "stream":
		return protocol.Stream{Session: coreSession, Input: stdin, Output: stdout,
			Build: protocol.Build{Version: buildVersion, Protocol: protocol.Version,
				GoVersion: runtime.Version()}}.Run(ctx)
	case "probe", "status":
		published, refreshErr := coreSession.Refresh(ctx)
		encoder := json.NewEncoder(stdout)
		encoder.SetEscapeHTML(false)
		if command == "probe" {
			err = encoder.Encode(struct {
				Revision   uint64             `json:"revision"`
				Connection session.Connection `json:"connection"`
				Identity   session.Identity   `json:"identity"`
				Lifecycle  systemduser.State  `json:"lifecycle"`
			}{published.Revision, published.State.Connection,
				published.State.Identity, published.State.Lifecycle})
		} else {
			err = encoder.Encode(published)
		}
		if err != nil {
			return err
		}
		return refreshErr
	}
	return nil
}

func parseOptions(flags *flag.FlagSet, args []string) (session.Config, bool, error) {
	var config session.Config
	var outputJSON bool
	var lifecycleKind string
	var probeSeconds int
	flags.StringVar(&config.Discovery.ConfigPath, "config", "", "Syncthing config.xml path")
	flags.StringVar(&config.Discovery.Endpoint, "endpoint", "", "explicit Syncthing endpoint")
	flags.StringVar(&config.Discovery.CredentialFile, "credential-file", "", "private API credential file")
	flags.StringVar(&config.Discovery.TLSCertificate, "tls-certificate", "", "pinned TLS certificate")
	flags.StringVar(&config.Discovery.ExpectedDeviceID, "expected-device-id", "", "expected Syncthing device ID")
	flags.BoolVar(&config.Discovery.InsecureTLS, "insecure-tls", false, "allow unverified TLS for this target")
	flags.StringVar(&config.HostID, "host-id", "standalone", "host adapter identity")
	flags.StringVar(&lifecycleKind, "lifecycle-kind", "", "authorized lifecycle kind")
	flags.BoolVar(&config.Lifecycle.Authorized, "lifecycle-authorized", false, "authorize the exact lifecycle binding")
	flags.StringVar(&config.Lifecycle.Unit, "lifecycle-unit", "", "exact systemd user unit")
	flags.StringVar(&config.Lifecycle.ConfigPath, "lifecycle-config", "", "config path bound to the unit")
	flags.IntVar(&probeSeconds, "probe-interval-seconds", 15, "lifecycle probe interval")
	flags.StringVar(&config.DesiredServiceState, "desired-service-state", "enabled", "persistent lifecycle intent")
	flags.BoolVar(&outputJSON, "json", false, "write JSON output")
	if err := flags.Parse(args); err != nil {
		return session.Config{}, false, errors.New("invalid command arguments")
	}
	if flags.NArg() != 0 {
		return session.Config{}, false, errors.New("unexpected command arguments")
	}
	if lifecycleKind != "" && lifecycleKind != "systemd-user" {
		return session.Config{}, false, errors.New("unsupported lifecycle kind")
	}
	if config.Lifecycle.Authorized && (lifecycleKind != "systemd-user" || config.Lifecycle.Unit == "") {
		return session.Config{}, false, errors.New("authorized lifecycle binding is incomplete")
	}
	if !config.Lifecycle.Authorized &&
		(lifecycleKind != "" || config.Lifecycle.Unit != "" || config.Lifecycle.ConfigPath != "") {
		return session.Config{}, false, errors.New("lifecycle binding requires explicit authority")
	}
	if probeSeconds < 1 || probeSeconds > 3600 {
		return session.Config{}, false, errors.New("probe interval must be between 1 and 3600 seconds")
	}
	if config.DesiredServiceState != "enabled" && config.DesiredServiceState != "disabled" {
		return session.Config{}, false, errors.New("desired service state must be enabled or disabled")
	}
	if config.HostID == "" || len(config.HostID) > 64 ||
		strings.IndexFunc(config.HostID, func(character rune) bool {
			return !(character >= 'a' && character <= 'z' ||
				character >= '0' && character <= '9' ||
				character == '.' || character == '_' || character == '-')
		}) >= 0 {
		return session.Config{}, false, errors.New("host identity is invalid")
	}
	if strings.ContainsAny(config.Lifecycle.Unit, "\r\n\x00") {
		return session.Config{}, false, errors.New("lifecycle unit is invalid")
	}
	config.ProbeInterval = time.Duration(probeSeconds) * time.Second
	return config, outputJSON, nil
}

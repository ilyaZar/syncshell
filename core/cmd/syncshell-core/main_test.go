package main

import (
	"flag"
	"io"
	"testing"
)

func TestParseOptionsRequiresExplicitLifecycleAuthority(t *testing.T) {
	flags := flag.NewFlagSet("test", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	_, _, err := parseOptions(flags, []string{
		"--host-id", "standalone",
		"--lifecycle-kind", "systemd-user",
		"--lifecycle-unit", "syncthing.service",
	})
	if err == nil {
		t.Fatal("unauthorized lifecycle binding succeeded")
	}
}

func TestParseOptionsAcceptsBoundedOperationalValues(t *testing.T) {
	flags := flag.NewFlagSet("test", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	config, outputJSON, err := parseOptions(flags, []string{
		"--host-id", "standalone",
		"--probe-interval-seconds", "2",
		"--desired-service-state", "disabled",
		"--lifecycle-kind", "systemd-user",
		"--lifecycle-authorized",
		"--lifecycle-unit", "syncthing.service",
		"--json",
	})
	if err != nil {
		t.Fatal(err)
	}
	if config.HostID != "standalone" || config.ProbeInterval.Seconds() != 2 ||
		config.DesiredServiceState != "disabled" || !config.Lifecycle.Authorized ||
		!outputJSON {
		t.Fatalf("unexpected config: %#v", config)
	}
}

func TestParseOptionsRejectsInvalidHostIdentity(t *testing.T) {
	flags := flag.NewFlagSet("test", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	_, _, err := parseOptions(flags, []string{"--host-id", "bad host"})
	if err == nil {
		t.Fatal("invalid host identity succeeded")
	}
}

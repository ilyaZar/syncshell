// Package systemduser owns one explicitly authorized user-service binding.
package systemduser

import (
	"context"
	"errors"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const maxShowOutput = 64 << 10

var validUnit = regexp.MustCompile(`^[A-Za-z0-9_.@:-]+[.]service$`)

// Binding is host authority for one exact systemd user unit.
type Binding struct {
	Authorized bool
	Unit       string
	ConfigPath string
}

// Target contains nonsecret facts needed to verify binding applicability.
type Target struct {
	ConfigPath string
	Local      bool
	Automatic  bool
}

// State is the bounded observed lifecycle state.
type State struct {
	Kind           string `json:"kind"`
	Unit           string `json:"unit,omitempty"`
	Classification string `json:"classification"`
	Available      bool   `json:"available"`
	Active         bool   `json:"active"`
	ActiveState    string `json:"activeState,omitempty"`
	UnitFileState  string `json:"unitFileState,omitempty"`
	Authorized     bool   `json:"authorized"`
	TargetMatch    bool   `json:"targetMatch"`
	CanControl     bool   `json:"canControl"`
	CanStart       bool   `json:"canStart"`
	DesiredState   string `json:"desiredState,omitempty"`
	Error          string `json:"error,omitempty"`
}

// Controller invokes systemctl directly because there is one concrete
// lifecycle backend in 0.1.8.
type Controller struct {
	Command string
}

// Probe observes the exact authorized unit after API state is known.
func (c Controller) Probe(
	ctx context.Context,
	binding Binding,
	target Target,
	apiOnline bool,
) State {
	state := State{Kind: "systemd-user", Unit: binding.Unit,
		Classification: "external", Authorized: binding.Authorized}
	if !binding.Authorized || !validUnit.MatchString(binding.Unit) {
		return state
	}

	properties, err := c.show(ctx, binding.Unit)
	if err != nil {
		state.Error = "could not inspect authorized user service"
		return state
	}
	state.ActiveState = bounded(properties["ActiveState"], 64)
	state.UnitFileState = bounded(properties["UnitFileState"], 64)
	state.Available = properties["LoadState"] == "loaded" &&
		properties["FragmentPath"] != ""
	state.Active = state.ActiveState == "active" ||
		state.ActiveState == "activating" || state.ActiveState == "reloading"
	state.TargetMatch = state.Available && targetMatches(binding, target, properties)

	if apiOnline && (!state.Active || !state.TargetMatch) {
		state.Classification = "external"
		return state
	}
	if state.Active {
		state.Classification = "unit-active-api-unavailable"
		if apiOnline {
			state.Classification = "managed"
		}
		state.CanControl = state.TargetMatch
		return state
	}
	if state.TargetMatch {
		state.Classification = "stopped-candidate"
		state.CanControl = true
		state.CanStart = true
	}
	return state
}

func (c Controller) show(ctx context.Context, unit string) (map[string]string, error) {
	command := c.Command
	if command == "" {
		command = "systemctl"
	}
	probeContext, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	output, err := exec.CommandContext(probeContext, command,
		"--user", "show", unit, "--no-pager",
		"--property=LoadState", "--property=ActiveState",
		"--property=UnitFileState", "--property=FragmentPath",
		"--property=ExecStart", "--property=Environment").Output()
	if err != nil {
		return nil, err
	}
	if len(output) > maxShowOutput {
		return nil, errors.New("systemctl output too large")
	}
	properties := make(map[string]string)
	for _, line := range strings.Split(string(output), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if ok {
			properties[key] = strings.TrimSpace(value)
		}
	}
	return properties, nil
}

func targetMatches(binding Binding, target Target, properties map[string]string) bool {
	if !target.Local || target.ConfigPath == "" {
		return false
	}
	selected := filepath.Clean(target.ConfigPath)
	if binding.ConfigPath != "" && filepath.Clean(binding.ConfigPath) != selected {
		return false
	}

	invocation := properties["ExecStart"] + " " + properties["Environment"]
	if configured := invocationConfigPath(invocation); configured != "" {
		return filepath.Clean(configured) == selected
	}
	if binding.ConfigPath != "" {
		return false
	}
	return target.Automatic
}

func invocationConfigPath(invocation string) string {
	fields := strings.Fields(strings.NewReplacer(";", " ", "\"", " ").Replace(invocation))
	for index, field := range fields {
		for _, prefix := range []string{"--config=", "--home=", "STCONFDIR=", "STHOMEDIR="} {
			if strings.HasPrefix(field, prefix) {
				value := strings.TrimPrefix(field, prefix)
				if prefix == "--home=" || prefix == "STCONFDIR=" || prefix == "STHOMEDIR=" {
					return filepath.Join(value, "config.xml")
				}
				return value
			}
		}
		if (field == "--config" || field == "--home") && index+1 < len(fields) {
			value := fields[index+1]
			if field == "--home" {
				return filepath.Join(value, "config.xml")
			}
			return value
		}
	}
	return ""
}

func bounded(value string, maximum int) string {
	value = strings.TrimSpace(value)
	if len(value) <= maximum {
		return value
	}
	return value[:maximum]
}

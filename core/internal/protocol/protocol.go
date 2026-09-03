// Package protocol owns bounded JSONL for session public types.
package protocol

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/session"
)

const (
	// Version is the only supported protocol major.
	Version = 1
	// MaxLineBytes bounds every input and output frame including its newline.
	MaxLineBytes = 1 << 20
	maxRequestID = 128
	maxRequests  = 4096
)

// Build describes the child implementation without source paths.
type Build struct {
	Version   string `json:"version"`
	Protocol  int    `json:"protocol"`
	GoVersion string `json:"goVersion"`
}

// Hello is the mandatory first output frame.
type Hello struct {
	V            int      `json:"v"`
	Type         string   `json:"type"`
	Build        Build    `json:"build"`
	Capabilities []string `json:"capabilities"`
}

// Snapshot is a complete session state frame.
type Snapshot struct {
	V        int              `json:"v"`
	Type     string           `json:"type"`
	Revision uint64           `json:"revision"`
	State    session.Snapshot `json:"state"`
}

// Result is exactly one response to an accepted request.
type Result struct {
	V        int            `json:"v"`
	Type     string         `json:"type"`
	ID       string         `json:"id"`
	OK       bool           `json:"ok"`
	Revision uint64         `json:"revision,omitempty"`
	Error    *session.Error `json:"error,omitempty"`
}

// Fatal is the final frame for an unrecoverable protocol error.
type Fatal struct {
	V       int    `json:"v"`
	Type    string `json:"type"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

// End marks a graceful stream end.
type End struct {
	V      int    `json:"v"`
	Type   string `json:"type"`
	Reason string `json:"reason"`
}

type request struct {
	V      int             `json:"v"`
	Type   string          `json:"type"`
	ID     string          `json:"id"`
	Config json.RawMessage `json:"config,omitempty"`
	Action string          `json:"action,omitempty"`
	Args   json.RawMessage `json:"args,omitempty"`
}

type input struct {
	line []byte
	err  error
}

// Stream runs one bounded request loop around one session.
type Stream struct {
	Session *session.Session
	Build   Build
	Input   io.Reader
	Output  io.Writer
}

// Run owns request decoding, periodic refresh, action routing, and output.
func (s Stream) Run(ctx context.Context) error {
	if s.Session == nil || s.Input == nil || s.Output == nil {
		return errors.New("protocol stream is incomplete")
	}
	if err := writeFrame(s.Output, Hello{V: Version, Type: "hello", Build: s.Build,
		Capabilities: []string{"complete-snapshots", "configure", "folder.rescan", "refresh"}}); err != nil {
		return err
	}
	initial, _ := s.Session.Refresh(ctx)
	if err := writeSnapshot(s.Output, initial); err != nil {
		return err
	}

	inputs := make(chan input, 1)
	readContext, cancelRead := context.WithCancel(ctx)
	defer cancelRead()
	go readLines(readContext, s.Input, inputs)

	timer := time.NewTimer(s.Session.ProbeInterval())
	defer timer.Stop()
	seen := make(map[string]struct{})
	for {
		select {
		case <-ctx.Done():
			return writeFrame(s.Output, End{V: Version, Type: "end", Reason: "canceled"})
		case <-timer.C:
			before := s.Session.Current().Revision
			published, _ := s.Session.Refresh(ctx)
			if published.Revision != before {
				if err := writeSnapshot(s.Output, published); err != nil {
					return err
				}
			}
			resetTimer(timer, s.Session.ProbeInterval())
		case incoming, ok := <-inputs:
			if !ok {
				return writeFrame(s.Output, End{V: Version, Type: "end", Reason: "stdin"})
			}
			if incoming.err != nil {
				code := "malformed_jsonl"
				if errors.Is(incoming.err, bufio.ErrTooLong) {
					code = "line_too_large"
				}
				_ = writeFrame(s.Output, Fatal{V: Version, Type: "fatal", Code: code,
					Message: "protocol input is invalid"})
				return incoming.err
			}
			shutdown, err := s.handleRequest(ctx, incoming.line, seen)
			if err != nil {
				_ = writeFrame(s.Output, Fatal{V: Version, Type: "fatal",
					Code: "protocol_request", Message: err.Error()})
				return err
			}
			if shutdown {
				return writeFrame(s.Output, End{V: Version, Type: "end", Reason: "shutdown"})
			}
			resetTimer(timer, s.Session.ProbeInterval())
		}
	}
}

func (s Stream) handleRequest(ctx context.Context, line []byte, seen map[string]struct{}) (bool, error) {
	request, err := validateRequest(line, seen)
	if err != nil {
		return false, err
	}
	switch request.Type {
	case "configure":
		return false, s.handleConfigure(request)
	case "refresh":
		return false, s.handleRefresh(ctx, request.ID)
	case "action":
		return false, s.handleAction(ctx, request)
	case "shutdown":
		if err := s.writeResult(request.ID,
			session.ActionResult{OK: true, Revision: s.Session.Current().Revision}); err != nil {
			return false, err
		}
		return true, nil
	default:
		return false, errors.New("request type is unsupported")
	}
}

func validateRequest(line []byte, seen map[string]struct{}) (request, error) {
	var decoded request
	if err := decodeStrict(line, &decoded); err != nil {
		return request{}, errors.New("request is malformed")
	}
	if decoded.V != Version {
		return request{}, errors.New("protocol major 1 required")
	}
	if decoded.ID == "" || len(decoded.ID) > maxRequestID ||
		strings.ContainsAny(decoded.ID, "\r\n\x00") {
		return request{}, errors.New("request id is invalid")
	}
	if _, exists := seen[decoded.ID]; exists {
		return request{}, errors.New("request id is duplicated")
	}
	if len(seen) >= maxRequests {
		return request{}, errors.New("request limit exceeded")
	}
	seen[decoded.ID] = struct{}{}
	return decoded, nil
}

func (s Stream) handleConfigure(request request) error {
	var config session.OperationalConfig
	if len(request.Config) == 0 || !rawObject(request.Config) ||
		decodeStrict(request.Config, &config) != nil {
		return s.writeResult(request.ID,
			session.ActionResult{Error: &session.Error{Code: "invalid_config",
				Message: "configuration request is invalid"}})
	}
	before := s.Session.Current().Revision
	result := s.Session.Configure(config)
	after := s.Session.Current()
	if after.Revision != before {
		if err := writeSnapshot(s.Output, after); err != nil {
			return err
		}
	}
	return s.writeResult(request.ID, result)
}

func (s Stream) handleRefresh(ctx context.Context, id string) error {
	before := s.Session.Current().Revision
	published, refreshErr := s.Session.Refresh(ctx)
	if published.Revision != before {
		if err := writeSnapshot(s.Output, published); err != nil {
			return err
		}
	}
	result := session.ActionResult{OK: refreshErr == nil, Revision: published.Revision}
	if refreshErr != nil {
		result.Error = published.State.Connection.Error
	}
	return s.writeResult(id, result)
}

func (s Stream) handleAction(ctx context.Context, request request) error {
	if request.Action != "folder.rescan" {
		return s.writeResult(request.ID,
			session.ActionResult{Error: &session.Error{Code: "unsupported_action",
				Message: "action is not supported"}})
	}
	var arguments struct {
		FolderID string `json:"folderId"`
	}
	if !rawObject(request.Args) || decodeStrict(request.Args, &arguments) != nil {
		return s.writeResult(request.ID,
			session.ActionResult{Error: &session.Error{Code: "invalid_action",
				Message: "action arguments are invalid"}})
	}
	before := s.Session.Current().Revision
	result := s.Session.Rescan(ctx, arguments.FolderID)
	after := s.Session.Current()
	if after.Revision != before {
		if err := writeSnapshot(s.Output, after); err != nil {
			return err
		}
	}
	return s.writeResult(request.ID, result)
}

func (s Stream) writeResult(id string, result session.ActionResult) error {
	return writeFrame(s.Output, Result{V: Version, Type: "result", ID: id,
		OK: result.OK, Revision: result.Revision, Error: result.Error})
}

func readLines(ctx context.Context, reader io.Reader, output chan<- input) {
	defer close(output)
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 64<<10), MaxLineBytes-1)
	for scanner.Scan() {
		line := append([]byte(nil), scanner.Bytes()...)
		select {
		case output <- input{line: line}:
		case <-ctx.Done():
			return
		}
	}
	if err := scanner.Err(); err != nil {
		select {
		case output <- input{err: normalizeScannerError(err)}:
		case <-ctx.Done():
		}
	}
}

func normalizeScannerError(err error) error {
	if strings.Contains(err.Error(), "token too long") {
		return bufio.ErrTooLong
	}
	return err
}

func writeSnapshot(writer io.Writer, published session.PublishedSnapshot) error {
	return writeFrame(writer, Snapshot{V: Version, Type: "snapshot",
		Revision: published.Revision, State: published.State})
}

// WritePublished writes one complete snapshot frame.
func WritePublished(writer io.Writer, published session.PublishedSnapshot) error {
	return writeSnapshot(writer, published)
}

func writeFrame(writer io.Writer, value any) error {
	encoded, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("encode protocol frame: %w", err)
	}
	if len(encoded)+1 > MaxLineBytes {
		return errors.New("protocol output exceeds line bound")
	}
	encoded = append(encoded, '\n')
	_, err = writer.Write(encoded)
	return err
}

func decodeStrict(data []byte, destination any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	var extra json.RawMessage
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("trailing JSON data")
	}
	return nil
}

func rawObject(value json.RawMessage) bool {
	trimmed := bytes.TrimSpace(value)
	return len(trimmed) >= 2 && trimmed[0] == '{' && trimmed[len(trimmed)-1] == '}'
}

func resetTimer(timer *time.Timer, duration time.Duration) {
	if !timer.Stop() {
		select {
		case <-timer.C:
		default:
		}
	}
	timer.Reset(duration)
}

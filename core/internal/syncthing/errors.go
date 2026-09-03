package syncthing

import (
	"context"
	"errors"
	"net"
	"net/url"
)

// ErrorCode identifies a stable connection failure class.
type ErrorCode string

const (
	ErrorCanceled     ErrorCode = "canceled"
	ErrorConfig       ErrorCode = "config"
	ErrorCredential   ErrorCode = "credential"
	ErrorAmbiguous    ErrorCode = "ambiguity"
	ErrorDNS          ErrorCode = "dns"
	ErrorConnection   ErrorCode = "connection"
	ErrorTimeout      ErrorCode = "timeout"
	ErrorTLS          ErrorCode = "tls"
	ErrorHTTP         ErrorCode = "http"
	ErrorUnauthorized ErrorCode = "unauthorized"
	ErrorSchema       ErrorCode = "schema"
	ErrorIdentity     ErrorCode = "identity"
)

// Error keeps internal causes out of public diagnostics.
type Error struct {
	Code    ErrorCode
	Op      string
	Message string
	Err     error
}

func (e *Error) Error() string {
	if e.Message != "" {
		return e.Message
	}
	if e.Op != "" {
		return e.Op + " failed"
	}
	return "Syncthing request failed"
}

func (e *Error) Unwrap() error { return e.Err }

func failure(code ErrorCode, op, message string, err error) error {
	return &Error{Code: code, Op: op, Message: message, Err: err}
}

func classifyNetwork(op string, err error) error {
	if errors.Is(err, context.Canceled) {
		return failure(ErrorCanceled, op, "request canceled", err)
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return failure(ErrorTimeout, op, "request timed out", err)
	}
	var netError net.Error
	if errors.As(err, &netError) && netError.Timeout() {
		return failure(ErrorTimeout, op, "request timed out", err)
	}
	var dnsError *net.DNSError
	if errors.As(err, &dnsError) {
		return failure(ErrorDNS, op, "target name could not be resolved", err)
	}
	var urlError *url.Error
	if errors.As(err, &urlError) {
		return classifyNetwork(op, urlError.Err)
	}
	return failure(ErrorConnection, op, "could not connect to Syncthing", err)
}

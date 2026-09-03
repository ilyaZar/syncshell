package syncthing

import (
	"net"
	"net/url"
	"path/filepath"
	"strings"
)

func normalizeEndpoint(value string, tlsEnabled bool) (string, string, bool, error) {
	address := strings.TrimSpace(value)
	if address == "" {
		return "", "", false, failure(ErrorConfig, "endpoint",
			"Syncthing GUI address is missing", nil)
	}
	if filepath.IsAbs(address) {
		return "unix://" + address, address, true, nil
	}
	if strings.Contains(address, "://") {
		return normalizeURL(address)
	}

	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return "", "", false, failure(ErrorConfig, "endpoint",
			"Syncthing GUI address is invalid", err)
	}
	host = normalizeHost(host)
	scheme := "http"
	if tlsEnabled {
		scheme = "https"
	}
	return scheme + "://" + net.JoinHostPort(host, port), "", isLoopback(host), nil
}

func normalizeURL(value string) (string, string, bool, error) {
	parsed, err := url.Parse(value)
	if err != nil {
		return "", "", false, failure(ErrorConfig, "endpoint",
			"Syncthing target URL is invalid", err)
	}
	switch parsed.Scheme {
	case "unix", "unixs":
		if !filepath.IsAbs(parsed.Path) || parsed.RawQuery != "" || parsed.Fragment != "" {
			return "", "", false, failure(ErrorConfig, "endpoint",
				"Syncthing Unix target is invalid", nil)
		}
		return parsed.Scheme + "://" + parsed.Path, parsed.Path, true, nil
	case "http", "https":
		if parsed.User != nil || parsed.Host == "" || parsed.Path != "" && parsed.Path != "/" ||
			parsed.RawQuery != "" || parsed.Fragment != "" {
			return "", "", false, failure(ErrorConfig, "endpoint",
				"Syncthing target URL is invalid", nil)
		}
		hostname := normalizeHost(parsed.Hostname())
		port := parsed.Port()
		if port == "" {
			if parsed.Scheme == "https" {
				port = "443"
			} else {
				port = "80"
			}
		}
		return parsed.Scheme + "://" + net.JoinHostPort(hostname, port), "", isLoopback(hostname), nil
	default:
		return "", "", false, failure(ErrorConfig, "endpoint",
			"Syncthing target scheme is unsupported", nil)
	}
}

func normalizeHost(host string) string {
	switch host {
	case "", "0.0.0.0", "*":
		return "127.0.0.1"
	case "::", "[::]":
		return "::1"
	default:
		return strings.Trim(host, "[]")
	}
}

func isLoopback(host string) bool {
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

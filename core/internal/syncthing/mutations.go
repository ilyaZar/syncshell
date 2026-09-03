package syncthing

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strconv"
)

// Folder reads one current folder configuration.
func (c *Client) Folder(ctx context.Context, folderID string) (Folder, error) {
	var response Folder
	path := "/rest/config/folders/" + url.PathEscape(folderID)
	err := c.request(ctx, http.MethodGet, path, nil, true, &response)
	return response, err
}

// PatchFolder applies one granular folder change.
func (c *Client) PatchFolder(ctx context.Context, folderID string, patch any) error {
	return c.jsonRequest(ctx, http.MethodPatch,
		"/rest/config/folders/"+url.PathEscape(folderID), patch, nil)
}

// DeleteFolder removes only the Syncthing folder record.
func (c *Client) DeleteFolder(ctx context.Context, folderID string) error {
	return c.request(ctx, http.MethodDelete,
		"/rest/config/folders/"+url.PathEscape(folderID), nil, true, nil)
}

// DefaultFolder reads the server's complete current folder template.
func (c *Client) DefaultFolder(ctx context.Context) (FolderConfig, error) {
	var response FolderConfig
	err := c.request(ctx, http.MethodGet, "/rest/config/defaults/folder", nil, true, &response)
	return response, err
}

// AddFolder posts one configuration built from the server default.
func (c *Client) AddFolder(ctx context.Context, config FolderConfig) error {
	return c.jsonRequest(ctx, http.MethodPost, "/rest/config/folders", config, nil)
}

// PendingFolders reads current unaccepted offers.
func (c *Client) PendingFolders(ctx context.Context) (PendingFolders, error) {
	var response PendingFolders
	err := c.request(ctx, http.MethodGet, "/rest/cluster/pending/folders", nil, true, &response)
	return response, err
}

// GUIConfig reads the current Syncthing GUI theme.
func (c *Client) GUIConfig(ctx context.Context) (GUIConfig, error) {
	var response GUIConfig
	err := c.request(ctx, http.MethodGet, "/rest/config/gui", nil, true, &response)
	return response, err
}

// SetGUITheme changes only the current Syncthing GUI theme.
func (c *Client) SetGUITheme(ctx context.Context, theme string) error {
	return c.jsonRequest(ctx, http.MethodPatch, "/rest/config/gui",
		map[string]string{"theme": theme}, nil)
}

// SystemPaths reads host-neutral runtime paths reported by Syncthing.
func (c *Client) SystemPaths(ctx context.Context) (SystemPaths, error) {
	var response SystemPaths
	err := c.request(ctx, http.MethodGet, "/rest/system/paths", nil, true, &response)
	return response, err
}

// FolderErrors reads current scan and pull errors.
func (c *Client) FolderErrors(ctx context.Context, folderID string) (FolderErrors, error) {
	var response FolderErrors
	path := "/rest/folder/errors?folder=" + url.QueryEscape(folderID) + "&page=1&perpage=100"
	err := c.requestWith(c.http, ctx, http.MethodGet, path, nil, true, &response,
		http.StatusNotFound)
	return response, err
}

// RandomString requests one strong folder-ID suggestion.
func (c *Client) RandomString(ctx context.Context, length int) (string, error) {
	var response RandomString
	path := "/rest/svc/random/string?length=" + strconv.Itoa(length)
	err := c.request(ctx, http.MethodGet, path, nil, true, &response)
	return response.Random, err
}

// FileInfo reads current local state for an indexed path.
func (c *Client) FileInfo(ctx context.Context, folderID, name string) (FileInfo, error) {
	var response FileInfo
	path := "/rest/db/file?folder=" + url.QueryEscape(folderID) +
		"&file=" + url.QueryEscape(name)
	err := c.request(ctx, http.MethodGet, path, nil, true, &response)
	return response, err
}

// RescanSubdirectory requests a narrow directory scan.
func (c *Client) RescanSubdirectory(ctx context.Context, folderID, subdirectory string) error {
	path := "/rest/db/scan?folder=" + url.QueryEscape(folderID) +
		"&sub=" + url.QueryEscape(subdirectory)
	return c.request(ctx, http.MethodPost, path, nil, true, nil)
}

func (c *Client) jsonRequest(
	ctx context.Context,
	method string,
	path string,
	value any,
	destination any,
) error {
	body, err := json.Marshal(value)
	if err != nil {
		return failure(ErrorSchema, "request", "could not encode Syncthing request", err)
	}
	return c.request(ctx, method, path, body, true, destination)
}

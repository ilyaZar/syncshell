package syncthing

import (
	"context"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// Events performs one bounded filtered Event API request.
func (c *Client) Events(
	ctx context.Context,
	since int64,
	limit int,
	timeoutSeconds int,
	types []string,
) ([]Event, error) {
	query := url.Values{}
	query.Set("since", strconv.FormatInt(since, 10))
	query.Set("limit", strconv.Itoa(limit))
	query.Set("timeout", strconv.Itoa(timeoutSeconds))
	if len(types) > 0 {
		query.Set("events", strings.Join(types, ","))
	}
	var response []Event
	err := c.requestWith(c.eventHTTP, ctx, http.MethodGet,
		"/rest/events?"+query.Encode(), nil, true, &response)
	return response, err
}

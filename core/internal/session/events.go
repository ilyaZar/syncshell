package session

import (
	"context"
	"time"

	"github.com/omarchy-QOL/syncshell/core/internal/syncthing"
)

const eventPollSeconds = 1

var eventTypes = []string{
	"ConfigSaved", "DeviceConnected", "DeviceDisconnected", "DownloadProgress",
	"FolderErrors", "FolderPaused", "FolderResumed", "FolderScanProgress",
	"FolderSummary", "ItemFinished", "ItemStarted", "LocalIndexUpdated",
	"PendingFoldersChanged", "RemoteDownloadProgress", "StateChanged",
	"StartupComplete",
}

// Updates starts the one Event API cursor and returns complete changed state.
func (s *Session) Updates(ctx context.Context) <-chan PublishedSnapshot {
	updates := make(chan PublishedSnapshot, 1)
	started := false
	s.eventsOnce.Do(func() {
		started = true
		go s.eventLoop(ctx, updates)
	})
	if !started {
		close(updates)
	}
	return updates
}

func (s *Session) eventLoop(ctx context.Context, updates chan PublishedSnapshot) {
	defer close(updates)
	cursor, retry := s.initializeEvents(ctx, updates)
	if retry < 0 {
		return
	}
	nextRefresh := time.Now().Add(s.RefreshInterval())
	nextLifecycle := time.Now().Add(s.ProbeInterval())
	nextActivity := time.Now().Add(activityCycle)
	for {
		events, err := s.client.Events(ctx, cursor, 256, eventPollSeconds, eventTypes)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			emitLatest(updates, s.setFresh(false))
			delay := retryDelay(retry)
			now := time.Now()
			for _, deadline := range []time.Time{
				nextRefresh, nextLifecycle, nextActivity,
			} {
				if remaining := deadline.Sub(now); remaining < delay {
					delay = max(0, remaining)
				}
			}
			if !waitContext(ctx, delay) {
				return
			}
			retry++
			s.reconcileScheduled(ctx, updates, time.Now(),
				&nextRefresh, &nextLifecycle, &nextActivity)
			continue
		}
		if retry > 0 {
			published, _ := s.Refresh(ctx)
			emitLatest(updates, published)
			nextRefresh = time.Now().Add(s.RefreshInterval())
			nextLifecycle = time.Now().Add(s.ProbeInterval())
			retry = 0
		}
		if len(events) > 0 {
			gap := eventDiscontinuity(cursor, events)
			cursor = events[len(events)-1].ID
			if gap || requiresHydration(events) {
				published, _ := s.Refresh(ctx)
				emitLatest(updates, published)
				nextRefresh = time.Now().Add(s.RefreshInterval())
				nextLifecycle = time.Now().Add(s.ProbeInterval())
			}
			if s.processActivityEvents(ctx, events, time.Now()) {
				emitLatest(updates, s.publishActivity(false, time.Now()))
			}
		}
		s.reconcileScheduled(ctx, updates, time.Now(),
			&nextRefresh, &nextLifecycle, &nextActivity)
	}
}

func (s *Session) reconcileScheduled(
	ctx context.Context,
	updates chan PublishedSnapshot,
	now time.Time,
	nextRefresh, nextLifecycle, nextActivity *time.Time,
) {
	select {
	case <-s.configChanged:
		*nextRefresh = now
		*nextLifecycle = now
	default:
	}
	if !now.Before(*nextActivity) {
		emitLatest(updates, s.publishActivity(true, now))
		*nextActivity = now.Add(activityCycle)
	}
	if !now.Before(*nextRefresh) {
		published, _ := s.Refresh(ctx)
		emitLatest(updates, published)
		*nextRefresh = now.Add(s.RefreshInterval())
		*nextLifecycle = now.Add(s.ProbeInterval())
	} else if !now.Before(*nextLifecycle) {
		emitLatest(updates, s.refreshLifecycle(ctx))
		*nextLifecycle = now.Add(s.ProbeInterval())
	}
}

func (s *Session) initializeEvents(
	ctx context.Context,
	updates chan PublishedSnapshot,
) (int64, int) {
	events, err := s.client.Events(ctx, 0, 1, 0, eventTypes)
	if err != nil {
		emitLatest(updates, s.setFresh(false))
		if ctx.Err() != nil {
			return 0, -1
		}
		return 0, 1
	}
	if len(events) == 0 {
		return 0, 0
	}
	return events[len(events)-1].ID, 0
}

func (s *Session) setFresh(fresh bool) PublishedSnapshot {
	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	if s.current.Revision != 0 && s.current.State.Connection.Fresh != fresh {
		s.current.State.Connection.Fresh = fresh
		s.current.Revision++
	}
	return clonePublished(s.current)
}

func eventDiscontinuity(cursor int64, events []syncthing.Event) bool {
	expected := cursor + 1
	for index, event := range events {
		if (cursor != 0 || index > 0) && event.ID != expected {
			return true
		}
		expected = event.ID + 1
	}
	return false
}

func requiresHydration(events []syncthing.Event) bool {
	for _, event := range events {
		switch event.Type {
		case "RemoteDownloadProgress", "DownloadProgress", "ItemStarted", "ItemFinished":
		default:
			return true
		}
	}
	return false
}

func retryDelay(attempt int) time.Duration {
	if attempt > 5 {
		attempt = 5
	}
	base := 250 * time.Millisecond * time.Duration(1<<attempt)
	jitter := time.Duration((attempt*97+53)%101) * time.Millisecond
	return base + jitter
}

func waitContext(ctx context.Context, duration time.Duration) bool {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func emitLatest(updates chan PublishedSnapshot, published PublishedSnapshot) {
	if published.Revision == 0 {
		return
	}
	select {
	case updates <- published:
		return
	default:
	}
	select {
	case <-updates:
	default:
	}
	select {
	case updates <- published:
	default:
	}
}

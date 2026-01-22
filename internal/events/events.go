// Package events provides append-only events.jsonl writing.
package events

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	// TypeSessionStart marks the start of a session.
	TypeSessionStart = "session_start"
	// TypeSessionComplete marks the completion of a session.
	TypeSessionComplete = "session_complete"
	// TypeNodeStart marks the start of a node.
	TypeNodeStart = "node_start"
	// TypeNodeComplete marks the completion of a node.
	TypeNodeComplete = "node_complete"
	// TypeIterationStart marks the start of an iteration.
	TypeIterationStart = "iteration_start"
	// TypeIterationComplete marks the completion of an iteration.
	TypeIterationComplete = "iteration_complete"
	// TypeError marks an error event.
	TypeError = "error"
)

var (
	// ErrMissingPath indicates the events file path is empty.
	ErrMissingPath = errors.New("events file path is empty")
	// ErrMissingType indicates the event type is empty.
	ErrMissingType = errors.New("event type is empty")
	// ErrMissingSession indicates the event session is empty.
	ErrMissingSession = errors.New("event session is empty")
)

// Cursor identifies a position within a session.
type Cursor struct {
	NodePath  string `json:"node_path,omitempty"`
	NodeRun   int    `json:"node_run,omitempty"`
	Iteration int    `json:"iteration,omitempty"`
	Provider  string `json:"provider,omitempty"`
}

// Event represents a single events.jsonl entry.
type Event struct {
	Timestamp string         `json:"ts"`
	Type      string         `json:"type"`
	Session   string         `json:"session"`
	Cursor    *Cursor        `json:"cursor"`
	Data      map[string]any `json:"data"`
}

// Writer appends events to a single events.jsonl file.
type Writer struct {
	path string
	mu   sync.Mutex
}

// NewWriter creates a writer for the given events.jsonl path.
func NewWriter(path string) *Writer {
	return &Writer{path: path}
}

// NewEvent constructs an event with a UTC RFC3339 timestamp.
func NewEvent(eventType, session string, cursor *Cursor, data map[string]any) Event {
	return Event{
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Type:      eventType,
		Session:   session,
		Cursor:    cursor,
		Data:      data,
	}
}

// Append writes an event to the writer's events.jsonl file.
func (w *Writer) Append(event Event) error {
	if w == nil {
		return errors.New("writer is nil")
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	return Append(w.path, event)
}

// Append writes an event to the provided events.jsonl path.
func Append(path string, event Event) error {
	path = strings.TrimSpace(path)
	if path == "" {
		return ErrMissingPath
	}

	event.Type = strings.TrimSpace(event.Type)
	if event.Type == "" {
		return ErrMissingType
	}
	event.Session = strings.TrimSpace(event.Session)
	if event.Session == "" {
		return ErrMissingSession
	}
	if event.Timestamp == "" {
		event.Timestamp = time.Now().UTC().Format(time.RFC3339)
	}
	if event.Data == nil {
		event.Data = map[string]any{}
	}

	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}
	payload = append(payload, '\n')

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create events dir: %w", err)
	}

	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return fmt.Errorf("open events file: %w", err)
	}
	defer func() {
		_ = file.Close()
	}()

	if err := lockExclusive(file); err != nil {
		return fmt.Errorf("lock events file: %w", err)
	}
	defer func() {
		_ = unlockExclusive(file)
	}()

	start, err := file.Seek(0, io.SeekEnd)
	if err != nil {
		return fmt.Errorf("seek events file: %w", err)
	}

	n, err := file.Write(payload)
	if err != nil || n != len(payload) {
		if truncateErr := file.Truncate(start); truncateErr != nil {
			if err != nil {
				return fmt.Errorf("write event: %w (truncate failed: %v)", err, truncateErr)
			}
			return fmt.Errorf("write event: %w (truncate failed: %v)", io.ErrShortWrite, truncateErr)
		}
		if err != nil {
			return fmt.Errorf("write event: %w", err)
		}
		return fmt.Errorf("write event: %w", io.ErrShortWrite)
	}
	return nil
}

func lockExclusive(file *os.File) error {
	return syscall.Flock(int(file.Fd()), syscall.LOCK_EX)
}

func unlockExclusive(file *os.File) error {
	return syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
}

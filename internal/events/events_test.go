package events

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAppendWritesEvent(t *testing.T) {
	dir := t.TempDir()
	eventsFile := filepath.Join(dir, "events.jsonl")

	cursor := &Cursor{
		NodePath:  "0",
		NodeRun:   1,
		Iteration: 2,
		Provider:  "codex",
	}
	event := NewEvent(TypeIterationStart, "session-one", cursor, map[string]any{"ok": true})

	if err := Append(eventsFile, event); err != nil {
		t.Fatalf("append: %v", err)
	}

	raw, err := os.ReadFile(eventsFile)
	if err != nil {
		t.Fatalf("read events file: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 1 {
		t.Fatalf("expected 1 event line, got %d", len(lines))
	}

	var stored Event
	if err := json.Unmarshal([]byte(lines[0]), &stored); err != nil {
		t.Fatalf("unmarshal event: %v", err)
	}

	if stored.Type != TypeIterationStart {
		t.Fatalf("expected type %q, got %q", TypeIterationStart, stored.Type)
	}
	if stored.Session != "session-one" {
		t.Fatalf("expected session %q, got %q", "session-one", stored.Session)
	}
	if stored.Timestamp == "" {
		t.Fatalf("expected timestamp to be set")
	}
	if stored.Cursor == nil || stored.Cursor.NodePath != "0" || stored.Cursor.Iteration != 2 || stored.Cursor.Provider != "codex" {
		t.Fatalf("unexpected cursor: %+v", stored.Cursor)
	}
	if ok, _ := stored.Data["ok"].(bool); !ok {
		t.Fatalf("expected data.ok=true, got %#v", stored.Data["ok"])
	}
}

func TestAppendDefaults(t *testing.T) {
	dir := t.TempDir()
	eventsFile := filepath.Join(dir, "events.jsonl")

	event := Event{Type: TypeSessionStart, Session: "session-defaults"}
	if err := Append(eventsFile, event); err != nil {
		t.Fatalf("append: %v", err)
	}

	raw, err := os.ReadFile(eventsFile)
	if err != nil {
		t.Fatalf("read events file: %v", err)
	}

	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 1 {
		t.Fatalf("expected 1 event line, got %d", len(lines))
	}

	var stored Event
	if err := json.Unmarshal([]byte(lines[0]), &stored); err != nil {
		t.Fatalf("unmarshal event: %v", err)
	}

	if stored.Cursor != nil {
		t.Fatalf("expected nil cursor, got %+v", stored.Cursor)
	}
	if stored.Data == nil || len(stored.Data) != 0 {
		t.Fatalf("expected empty data map, got %#v", stored.Data)
	}
	if stored.Timestamp == "" {
		t.Fatalf("expected timestamp to be set")
	}
}

func TestAppendMultipleEvents(t *testing.T) {
	dir := t.TempDir()
	eventsFile := filepath.Join(dir, "events.jsonl")

	if err := Append(eventsFile, Event{Type: TypeSessionStart, Session: "session-multi"}); err != nil {
		t.Fatalf("append first: %v", err)
	}
	if err := Append(eventsFile, Event{Type: TypeSessionComplete, Session: "session-multi"}); err != nil {
		t.Fatalf("append second: %v", err)
	}

	raw, err := os.ReadFile(eventsFile)
	if err != nil {
		t.Fatalf("read events file: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 event lines, got %d", len(lines))
	}
}

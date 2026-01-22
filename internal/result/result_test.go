package result

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestNormalizeDefaults(t *testing.T) {
	t.Parallel()

	normalized := Normalize(Result{})
	if normalized.Signals.Risk != "low" {
		t.Fatalf("risk default mismatch: got %q", normalized.Signals.Risk)
	}
	if normalized.Work.ItemsCompleted == nil || normalized.Work.FilesTouched == nil {
		t.Fatalf("work slices should be initialized")
	}
	if normalized.Artifacts.Outputs == nil || normalized.Artifacts.Paths == nil {
		t.Fatalf("artifact slices should be initialized")
	}
}

func TestFromStatusConversion(t *testing.T) {
	t.Parallel()

	status := Status{
		Decision: "stop",
		Reason:   "done",
		Summary:  "wrapped",
		Work: WorkInfo{
			ItemsCompleted: []string{"item"},
			FilesTouched:   []string{"file.go"},
		},
		Errors: []string{"boom"},
	}
	normalized := FromStatus(status)

	if normalized.Summary != "wrapped" {
		t.Fatalf("summary mismatch: got %q", normalized.Summary)
	}
	if normalized.Decision != "stop" {
		t.Fatalf("decision mismatch: got %q", normalized.Decision)
	}
	if normalized.Signals.PlateauSuspected {
		t.Fatalf("plateau_suspected should default to false")
	}
	if normalized.Signals.Risk != "low" {
		t.Fatalf("risk default mismatch: got %q", normalized.Signals.Risk)
	}
	if normalized.Signals.Notes != "done" {
		t.Fatalf("notes mismatch: got %q", normalized.Signals.Notes)
	}
	if len(normalized.Errors) != 1 || normalized.Errors[0] != "boom" {
		t.Fatalf("errors mismatch: %#v", normalized.Errors)
	}
	if normalized.Artifacts.Outputs == nil || len(normalized.Artifacts.Outputs) != 0 {
		t.Fatalf("outputs should default to empty slice")
	}
}

func TestNormalizeFilesPrefersResult(t *testing.T) {
	t.Parallel()

	tempDir := t.TempDir()
	resultPath := filepath.Join(tempDir, "result.json")
	statusPath := filepath.Join(tempDir, "status.json")

	if err := os.WriteFile(resultPath, []byte(`{"summary":"from result","signals":{"plateau_suspected":true,"risk":"high","notes":"note"}}`), 0o644); err != nil {
		t.Fatalf("write result.json: %v", err)
	}
	if err := os.WriteFile(statusPath, []byte(`{"summary":"from status","decision":"stop"}`), 0o644); err != nil {
		t.Fatalf("write status.json: %v", err)
	}

	result, source, err := NormalizeFiles(resultPath, statusPath)
	if err != nil {
		t.Fatalf("NormalizeFiles: %v", err)
	}
	if source != SourceResult {
		t.Fatalf("source mismatch: got %q", source)
	}
	if result.Summary != "from result" {
		t.Fatalf("summary mismatch: got %q", result.Summary)
	}

	var reloaded Result
	if err := readJSON(resultPath, &reloaded); err != nil {
		t.Fatalf("read result.json: %v", err)
	}
	if reloaded.Work.ItemsCompleted == nil || reloaded.Artifacts.Outputs == nil {
		t.Fatalf("normalized result should include slice defaults")
	}
}

func TestNormalizeFilesFallsBackToStatus(t *testing.T) {
	t.Parallel()

	tempDir := t.TempDir()
	resultPath := filepath.Join(tempDir, "result.json")
	statusPath := filepath.Join(tempDir, "status.json")

	if err := os.WriteFile(statusPath, []byte(`{"decision":"continue","reason":"ok","summary":"from status","work":{"items_completed":["a"],"files_touched":["b.go"]}}`), 0o644); err != nil {
		t.Fatalf("write status.json: %v", err)
	}

	result, source, err := NormalizeFiles(resultPath, statusPath)
	if err != nil {
		t.Fatalf("NormalizeFiles: %v", err)
	}
	if source != SourceStatus {
		t.Fatalf("source mismatch: got %q", source)
	}
	if result.Summary != "from status" {
		t.Fatalf("summary mismatch: got %q", result.Summary)
	}
	if result.Signals.Notes != "ok" {
		t.Fatalf("notes mismatch: got %q", result.Signals.Notes)
	}

	if _, err := os.Stat(resultPath); err != nil {
		t.Fatalf("result.json should be written: %v", err)
	}
}

func TestNormalizeFilesRejectsInvalidResult(t *testing.T) {
	t.Parallel()

	tempDir := t.TempDir()
	resultPath := filepath.Join(tempDir, "result.json")
	statusPath := filepath.Join(tempDir, "status.json")

	if err := os.WriteFile(resultPath, []byte("{bad"), 0o644); err != nil {
		t.Fatalf("write result.json: %v", err)
	}
	if err := os.WriteFile(statusPath, []byte(`{"decision":"continue"}`), 0o644); err != nil {
		t.Fatalf("write status.json: %v", err)
	}

	_, _, err := NormalizeFiles(resultPath, statusPath)
	if err == nil {
		t.Fatalf("expected error for invalid result.json")
	}
	if !errors.Is(err, ErrResultInvalid) {
		t.Fatalf("expected ErrResultInvalid, got %v", err)
	}
}

func TestNormalizeFilesMissing(t *testing.T) {
	t.Parallel()

	tempDir := t.TempDir()
	resultPath := filepath.Join(tempDir, "result.json")
	statusPath := filepath.Join(tempDir, "status.json")

	_, _, err := NormalizeFiles(resultPath, statusPath)
	if err == nil {
		t.Fatalf("expected error when both files are missing")
	}
	if !errors.Is(err, ErrResultMissing) {
		t.Fatalf("expected ErrResultMissing, got %v", err)
	}
}

func readJSON(path string, target any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, target)
}

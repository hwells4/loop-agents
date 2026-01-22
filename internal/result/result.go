// Package result normalizes agent result payloads across legacy and v3 schemas.
package result

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var (
	// ErrResultMissing indicates neither result nor status payloads were found.
	ErrResultMissing = errors.New("result missing")
	// ErrResultInvalid indicates result.json could not be parsed.
	ErrResultInvalid = errors.New("result invalid")
	// ErrStatusInvalid indicates status.json could not be parsed.
	ErrStatusInvalid = errors.New("status invalid")
)

// Source identifies the file origin of a normalized result.
type Source string

const (
	// SourceResult indicates the result originated from result.json.
	SourceResult Source = "result"
	// SourceStatus indicates the result originated from status.json.
	SourceStatus Source = "status"
)

// Result is the v3 result schema with optional legacy fields.
type Result struct {
	Summary   string       `json:"summary"`
	Work      WorkInfo     `json:"work"`
	Artifacts ArtifactInfo `json:"artifacts"`
	Signals   SignalInfo   `json:"signals"`
	Errors    []string     `json:"errors,omitempty"`
	Decision  string       `json:"decision,omitempty"`
	Reason    string       `json:"reason,omitempty"`
}

// WorkInfo captures work completed by an agent.
type WorkInfo struct {
	ItemsCompleted []string `json:"items_completed"`
	FilesTouched   []string `json:"files_touched"`
}

// ArtifactInfo captures produced outputs.
type ArtifactInfo struct {
	Outputs []string `json:"outputs"`
	Paths   []string `json:"paths"`
}

// SignalInfo captures advisory signals for termination.
type SignalInfo struct {
	PlateauSuspected bool   `json:"plateau_suspected"`
	Risk             string `json:"risk"`
	Notes            string `json:"notes"`
}

// Status is the legacy v2 status.json schema.
type Status struct {
	Decision string   `json:"decision"`
	Reason   string   `json:"reason"`
	Summary  string   `json:"summary"`
	Work     WorkInfo `json:"work"`
	Errors   []string `json:"errors,omitempty"`
}

// Normalize ensures a Result uses defaults for missing fields and slices.
func Normalize(input Result) Result {
	normalized := input
	normalized.Work.ItemsCompleted = normalizeSlice(normalized.Work.ItemsCompleted)
	normalized.Work.FilesTouched = normalizeSlice(normalized.Work.FilesTouched)
	normalized.Artifacts.Outputs = normalizeSlice(normalized.Artifacts.Outputs)
	normalized.Artifacts.Paths = normalizeSlice(normalized.Artifacts.Paths)

	normalized.Signals.Risk = strings.TrimSpace(normalized.Signals.Risk)
	if normalized.Signals.Risk == "" {
		normalized.Signals.Risk = "low"
	}
	return normalized
}

// FromStatus converts a legacy status.json payload into a normalized Result.
func FromStatus(status Status) Result {
	result := Result{
		Summary:  status.Summary,
		Work:     status.Work,
		Errors:   status.Errors,
		Decision: status.Decision,
		Reason:   status.Reason,
		Artifacts: ArtifactInfo{
			Outputs: []string{},
			Paths:   []string{},
		},
		Signals: SignalInfo{
			PlateauSuspected: false,
			Risk:             "low",
			Notes:            status.Reason,
		},
	}
	return Normalize(result)
}

// Load resolves a normalized Result from result.json or status.json, preferring result.json.
func Load(resultPath, statusPath string) (Result, Source, error) {
	if strings.TrimSpace(resultPath) != "" {
		loaded, err := readResultFile(resultPath)
		if err == nil {
			return Normalize(loaded), SourceResult, nil
		}
		if !errors.Is(err, os.ErrNotExist) {
			return Result{}, SourceResult, fmt.Errorf("read result: %w", err)
		}
	}

	if strings.TrimSpace(statusPath) == "" {
		return Result{}, "", ErrResultMissing
	}

	status, err := readStatusFile(statusPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Result{}, SourceStatus, ErrResultMissing
		}
		return Result{}, SourceStatus, fmt.Errorf("read status: %w", err)
	}
	return FromStatus(status), SourceStatus, nil
}

// NormalizeFiles loads, normalizes, and writes result.json if a path is supplied.
func NormalizeFiles(resultPath, statusPath string) (Result, Source, error) {
	normalized, source, err := Load(resultPath, statusPath)
	if err != nil {
		return Result{}, source, err
	}
	if strings.TrimSpace(resultPath) == "" {
		return normalized, source, nil
	}
	if err := Write(resultPath, normalized); err != nil {
		return Result{}, source, err
	}
	return normalized, source, nil
}

// Write writes a normalized result.json payload to disk.
func Write(path string, result Result) error {
	if strings.TrimSpace(path) == "" {
		return errors.New("result path is empty")
	}
	normalized := Normalize(result)
	payload, err := json.MarshalIndent(normalized, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal result: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create result dir: %w", err)
	}
	if err := os.WriteFile(path, append(payload, '\n'), 0o644); err != nil {
		return fmt.Errorf("write result: %w", err)
	}
	return nil
}

func readResultFile(path string) (Result, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Result{}, err
	}
	var result Result
	if err := json.Unmarshal(data, &result); err != nil {
		return Result{}, fmt.Errorf("%w: %v", ErrResultInvalid, err)
	}
	return result, nil
}

func readStatusFile(path string) (Status, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Status{}, err
	}
	var status Status
	if err := json.Unmarshal(data, &status); err != nil {
		return Status{}, fmt.Errorf("%w: %v", ErrStatusInvalid, err)
	}
	return status, nil
}

func normalizeSlice(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

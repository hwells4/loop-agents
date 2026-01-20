package provider

import (
	"context"
	"time"
)

// Request defines the data required to invoke a provider.
type Request struct {
	Prompt  string
	Model   string
	Env     map[string]string
	WorkDir string
}

// Result captures provider execution output and metadata.
type Result struct {
	Output     string
	ExitCode   int
	Model      string
	StartedAt  time.Time
	FinishedAt time.Time
	Duration   time.Duration
}

// Provider is the execution interface for agent backends.
type Provider interface {
	Name() string
	DefaultModel() string
	Invoke(ctx context.Context, req Request) (Result, error)
}

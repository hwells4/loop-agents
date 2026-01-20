package provider

import (
	"context"
	"time"
)

// Request defines the data required to execute a provider.
type Request struct {
	// Prompt is the text to send to the agent.
	Prompt string

	// Model specifies the model to use. Empty uses provider default.
	Model string

	// Env contains additional environment variables.
	Env map[string]string

	// WorkDir is the working directory for execution.
	WorkDir string

	// Config contains provider-specific configuration.
	Config map[string]any

	// StatusPath is where the agent should write status.json.
	StatusPath string

	// ResultPath is where the agent should write result.json.
	ResultPath string
}

// Result captures provider execution output and metadata.
type Result struct {
	// Output is the combined stdout (legacy compatibility).
	Output string

	// Stdout is the standard output stream.
	Stdout string

	// Stderr is the standard error stream.
	Stderr string

	// ExitCode is the process exit code.
	ExitCode int

	// Model is the model that was used.
	Model string

	// StartedAt is when execution began.
	StartedAt time.Time

	// FinishedAt is when execution completed.
	FinishedAt time.Time

	// Duration is the execution time.
	Duration time.Duration
}

// Capability flags for provider features.
type Capability uint32

const (
	// CapabilityNone indicates no special capabilities.
	CapabilityNone Capability = 0

	// CapabilityStreaming indicates the provider supports streaming output.
	CapabilityStreaming Capability = 1 << iota

	// CapabilityTools indicates the provider supports tool use.
	CapabilityTools

	// CapabilityVision indicates the provider supports image input.
	CapabilityVision
)

// Capabilities describes what a provider can do.
type Capabilities struct {
	// Flags is a bitmask of Capability values.
	Flags Capability

	// SupportedModels lists models this provider supports.
	SupportedModels []string

	// MaxPromptSize is the maximum prompt size in bytes.
	MaxPromptSize int64

	// MaxOutputSize is the maximum output size in bytes.
	MaxOutputSize int64
}

// Has checks if a capability is present.
func (c Capabilities) Has(cap Capability) bool {
	return c.Flags&cap != 0
}

// Provider is the execution interface for agent backends.
type Provider interface {
	// Name returns the canonical provider name.
	Name() string

	// DefaultModel returns the default model for this provider.
	DefaultModel() string

	// Init initializes the provider. Called once before any Execute calls.
	Init(ctx context.Context) error

	// Shutdown cleanly shuts down the provider. Called when done.
	Shutdown(ctx context.Context) error

	// Validate checks if the provider is properly configured.
	Validate() error

	// Capabilities returns the provider's feature set.
	Capabilities() Capabilities

	// Execute runs the agent with the given request.
	Execute(ctx context.Context, req Request) (Result, error)
}

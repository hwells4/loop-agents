package claude

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"

	"github.com/dodo-digital/agent-pipelines/pkg/provider"
)

const (
	// DefaultBinary is the CLI name used to invoke Claude.
	DefaultBinary = "claude"
	// DefaultModel is the default Claude model.
	DefaultModel = "opus"
)

// CLI invokes the Claude CLI as a provider implementation.
type CLI struct {
	Binary          string
	Model           string
	SkipPermissions bool
}

// Option configures the Claude CLI provider.
type Option func(*CLI)

// New returns a Claude CLI provider with defaults applied.
func New(options ...Option) *CLI {
	cli := &CLI{
		Binary:          DefaultBinary,
		Model:           DefaultModel,
		SkipPermissions: true,
	}
	for _, option := range options {
		option(cli)
	}
	return cli
}

// WithBinary overrides the claude CLI binary name.
func WithBinary(binary string) Option {
	return func(cli *CLI) {
		if binary != "" {
			cli.Binary = binary
		}
	}
}

// WithDefaultModel overrides the default Claude model.
func WithDefaultModel(model string) Option {
	return func(cli *CLI) {
		if model != "" {
			cli.Model = model
		}
	}
}

// WithSkipPermissions toggles the --dangerously-skip-permissions flag.
func WithSkipPermissions(skip bool) Option {
	return func(cli *CLI) {
		cli.SkipPermissions = skip
	}
}

// Name returns the canonical provider name.
func (c *CLI) Name() string {
	return "claude"
}

// DefaultModel returns the default model for Claude.
func (c *CLI) DefaultModel() string {
	if c.Model != "" {
		return c.Model
	}
	return DefaultModel
}

// Invoke executes the Claude CLI with the supplied prompt and model.
func (c *CLI) Invoke(ctx context.Context, req provider.Request) (provider.Result, error) {
	model := req.Model
	if model == "" {
		model = c.DefaultModel()
	}
	model = normalizeModel(model)

	binary := c.Binary
	if binary == "" {
		binary = DefaultBinary
	}
	if _, err := exec.LookPath(binary); err != nil {
		return provider.Result{Model: model, ExitCode: -1}, fmt.Errorf("claude binary not found: %w", err)
	}

	args := []string{"--model", model}
	if c.SkipPermissions {
		args = append(args, "--dangerously-skip-permissions")
	}

	cmd := exec.CommandContext(ctx, binary, args...)
	if req.WorkDir != "" {
		cmd.Dir = req.WorkDir
	}
	if len(req.Env) > 0 {
		cmd.Env = append(os.Environ(), formatEnv(req.Env)...)
	}
	cmd.Stdin = strings.NewReader(req.Prompt)

	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output

	started := time.Now()
	err := cmd.Run()
	finished := time.Now()

	result := provider.Result{
		Output:     output.String(),
		ExitCode:   exitCode(err),
		Model:      model,
		StartedAt:  started,
		FinishedAt: finished,
		Duration:   finished.Sub(started),
	}
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return result, err
		}
		return result, err
	}
	return result, nil
}

func normalizeModel(model string) string {
	switch strings.ToLower(strings.TrimSpace(model)) {
	case "claude-opus", "opus-4", "opus-4.5":
		return "opus"
	case "claude-sonnet", "sonnet-4":
		return "sonnet"
	case "claude-haiku":
		return "haiku"
	default:
		return model
	}
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

func formatEnv(env map[string]string) []string {
	keys := make([]string, 0, len(env))
	for key := range env {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	formatted := make([]string, 0, len(keys))
	for _, key := range keys {
		formatted = append(formatted, fmt.Sprintf("%s=%s", key, env[key]))
	}
	return formatted
}

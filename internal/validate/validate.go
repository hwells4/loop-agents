// Package validate provides input validation for security-sensitive operations.
// It addresses multiple security vulnerabilities: environment injection,
// path traversal, prompt injection via size, model/binary allowlisting, and
// provider name validation.
package validate

import (
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

// Default limits and allowlists.
const (
	// DefaultMaxPromptSize is the default maximum prompt size (10 MiB).
	DefaultMaxPromptSize = 10 * 1024 * 1024

	// MaxProviderNameLength is the maximum length for provider names.
	MaxProviderNameLength = 64
)

var (
	// ErrEnvKeyInvalid indicates an environment variable key contains invalid characters.
	ErrEnvKeyInvalid = errors.New("invalid environment variable key")

	// ErrEnvValueBlocked indicates an environment variable is on the block list.
	ErrEnvValueBlocked = errors.New("blocked environment variable")

	// ErrWorkDirTraversal indicates a path traversal attempt was detected.
	ErrWorkDirTraversal = errors.New("path traversal detected")

	// ErrPromptTooLarge indicates the prompt exceeds the size limit.
	ErrPromptTooLarge = errors.New("prompt exceeds size limit")

	// ErrModelNotAllowed indicates the model is not in the allowlist.
	ErrModelNotAllowed = errors.New("model not in allowlist")

	// ErrBinaryNotAllowed indicates the binary is not in the allowlist.
	ErrBinaryNotAllowed = errors.New("binary not in allowlist")

	// ErrProviderNameInvalid indicates the provider name doesn't match the required pattern.
	ErrProviderNameInvalid = errors.New("invalid provider name")
)

// blockedEnvKeys contains environment variables that could be used for injection attacks.
// These are blocked regardless of value.
var blockedEnvKeys = map[string]bool{
	"LD_PRELOAD":      true,
	"LD_LIBRARY_PATH": true,
	"PATH":            true,
	"DYLD_INSERT_LIBRARIES": true,
	"DYLD_LIBRARY_PATH":     true,
	"LD_AUDIT":              true,
	"LD_DEBUG":              true,
	"LD_SHOW_AUXV":          true,
	"LD_TRACE_LOADED_OBJECTS": true,
}

// AllowedBinaries contains the only binaries we allow for provider execution.
var AllowedBinaries = map[string]bool{
	"claude": true,
	"codex":  true,
}

// providerNamePattern matches valid provider names: lowercase letter followed by
// up to 63 lowercase alphanumeric chars or hyphens.
var providerNamePattern = regexp.MustCompile(`^[a-z][a-z0-9-]{0,63}$`)

// EnvKey validates an environment variable key.
// Returns error if the key contains newlines, null bytes, or equals signs.
func EnvKey(key string) error {
	if key == "" {
		return fmt.Errorf("%w: key is empty", ErrEnvKeyInvalid)
	}
	if strings.ContainsAny(key, "\x00\n\r=") {
		return fmt.Errorf("%w: key contains forbidden characters", ErrEnvKeyInvalid)
	}
	return nil
}

// EnvValue validates an environment variable key-value pair.
// Returns error if the key is on the block list or invalid.
func EnvValue(key, value string) error {
	if err := EnvKey(key); err != nil {
		return err
	}
	upperKey := strings.ToUpper(key)
	if blockedEnvKeys[upperKey] {
		return fmt.Errorf("%w: %s", ErrEnvValueBlocked, key)
	}
	// Block values containing null bytes
	if strings.Contains(value, "\x00") {
		return fmt.Errorf("%w: value contains null byte", ErrEnvKeyInvalid)
	}
	return nil
}

// WorkDir validates and canonicalizes a working directory path.
// Returns the cleaned path or error if traversal is detected.
func WorkDir(path string) (string, error) {
	if path == "" {
		return "", nil
	}

	// Clean the path first
	cleaned := filepath.Clean(path)

	// Reject paths with .. after cleaning that still escape
	if !filepath.IsAbs(cleaned) {
		// Convert to absolute for traversal check
		abs, err := filepath.Abs(cleaned)
		if err != nil {
			return "", fmt.Errorf("%w: failed to resolve path: %v", ErrWorkDirTraversal, err)
		}
		cleaned = abs
	}

	// Check for .. components in the cleaned path
	if strings.Contains(cleaned, "..") {
		return "", fmt.Errorf("%w: path contains '..'", ErrWorkDirTraversal)
	}

	return cleaned, nil
}

// Prompt validates prompt size against a maximum.
// If maxSize is 0, DefaultMaxPromptSize is used.
func Prompt(prompt string, maxSize int) error {
	if maxSize <= 0 {
		maxSize = DefaultMaxPromptSize
	}
	if len(prompt) > maxSize {
		return fmt.Errorf("%w: %d bytes exceeds %d byte limit", ErrPromptTooLarge, len(prompt), maxSize)
	}
	return nil
}

// Model validates a model name against an allowlist.
// Returns error if the model is not in the allowlist.
func Model(model string, allowlist []string) error {
	if len(allowlist) == 0 {
		// No allowlist = allow all
		return nil
	}
	model = strings.ToLower(strings.TrimSpace(model))
	for _, allowed := range allowlist {
		if strings.ToLower(strings.TrimSpace(allowed)) == model {
			return nil
		}
	}
	return fmt.Errorf("%w: %q", ErrModelNotAllowed, model)
}

// Binary validates a binary name against the allowed binaries list.
func Binary(binary string) error {
	binary = strings.ToLower(strings.TrimSpace(binary))
	if binary == "" {
		return fmt.Errorf("%w: binary name is empty", ErrBinaryNotAllowed)
	}
	// Extract just the binary name if it's a path
	binary = filepath.Base(binary)
	if !AllowedBinaries[binary] {
		return fmt.Errorf("%w: %q", ErrBinaryNotAllowed, binary)
	}
	return nil
}

// ProviderName validates a provider name against the required pattern.
// Valid names: start with lowercase letter, followed by lowercase alphanumeric or hyphen,
// max 64 characters total.
func ProviderName(name string) error {
	if name == "" {
		return fmt.Errorf("%w: name is empty", ErrProviderNameInvalid)
	}
	if !providerNamePattern.MatchString(name) {
		return fmt.Errorf("%w: %q does not match pattern ^[a-z][a-z0-9-]{0,63}$", ErrProviderNameInvalid, name)
	}
	return nil
}

// Env validates all key-value pairs in an environment map.
func Env(env map[string]string) error {
	for k, v := range env {
		if err := EnvValue(k, v); err != nil {
			return err
		}
	}
	return nil
}

// Request validates all fields of a provider request.
// This is a convenience function that combines all validators.
type RequestConfig struct {
	MaxPromptSize   int
	ModelAllowlist  []string
	BinaryAllowlist []string
}

// DefaultClaudeModels is the default allowlist for Claude models.
var DefaultClaudeModels = []string{
	"opus", "opus-4", "opus-4.5", "claude-opus",
	"sonnet", "sonnet-4", "claude-sonnet",
	"haiku", "claude-haiku",
}

// DefaultCodexModels is the default allowlist for Codex models.
var DefaultCodexModels = []string{
	"gpt-5.2-codex", "gpt-5-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini",
	"o3", "o3-mini",
}

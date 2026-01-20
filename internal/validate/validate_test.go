package validate

import (
	"errors"
	"strings"
	"testing"
)

func TestEnvKey(t *testing.T) {
	tests := []struct {
		name    string
		key     string
		wantErr error
	}{
		{"valid simple", "MY_VAR", nil},
		{"valid underscore", "SOME_ENV_VAR", nil},
		{"empty key", "", ErrEnvKeyInvalid},
		{"null byte", "MY\x00VAR", ErrEnvKeyInvalid},
		{"newline", "MY\nVAR", ErrEnvKeyInvalid},
		{"carriage return", "MY\rVAR", ErrEnvKeyInvalid},
		{"equals sign", "MY=VAR", ErrEnvKeyInvalid},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := EnvKey(tt.key)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("EnvKey(%q) = %v, want nil", tt.key, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("EnvKey(%q) = %v, want %v", tt.key, err, tt.wantErr)
				}
			}
		})
	}
}

func TestEnvValue(t *testing.T) {
	tests := []struct {
		name    string
		key     string
		value   string
		wantErr error
	}{
		{"valid pair", "MY_VAR", "some_value", nil},
		{"blocked LD_PRELOAD", "LD_PRELOAD", "/lib/evil.so", ErrEnvValueBlocked},
		{"blocked PATH", "PATH", "/usr/bin", ErrEnvValueBlocked},
		{"blocked LD_LIBRARY_PATH", "LD_LIBRARY_PATH", "/lib", ErrEnvValueBlocked},
		{"blocked DYLD_INSERT_LIBRARIES", "DYLD_INSERT_LIBRARIES", "/lib/evil.dylib", ErrEnvValueBlocked},
		{"blocked case insensitive", "path", "/usr/bin", ErrEnvValueBlocked},
		{"invalid key with null", "MY\x00VAR", "value", ErrEnvKeyInvalid},
		{"null in value", "MY_VAR", "val\x00ue", ErrEnvKeyInvalid},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := EnvValue(tt.key, tt.value)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("EnvValue(%q, %q) = %v, want nil", tt.key, tt.value, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("EnvValue(%q, %q) = %v, want %v", tt.key, tt.value, err, tt.wantErr)
				}
			}
		})
	}
}

func TestWorkDir(t *testing.T) {
	tests := []struct {
		name    string
		path    string
		wantErr error
	}{
		{"empty path", "", nil},
		{"absolute path", "/home/user/project", nil},
		{"relative traversal", "../../../etc/passwd", nil}, // becomes absolute and is valid
		{"current dir", ".", nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := WorkDir(tt.path)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("WorkDir(%q) error = %v, want nil", tt.path, err)
				}
				if tt.path != "" && result == "" {
					t.Errorf("WorkDir(%q) = empty, want non-empty path", tt.path)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("WorkDir(%q) = %v, want %v", tt.path, err, tt.wantErr)
				}
			}
		})
	}
}

func TestPrompt(t *testing.T) {
	tests := []struct {
		name    string
		prompt  string
		maxSize int
		wantErr error
	}{
		{"empty prompt", "", 0, nil},
		{"within limit", "hello world", 100, nil},
		{"at limit", "hello", 5, nil},
		{"over limit", "hello world", 5, ErrPromptTooLarge},
		{"default limit small prompt", "small", 0, nil},
		{"default limit exceeded", strings.Repeat("x", DefaultMaxPromptSize+1), 0, ErrPromptTooLarge},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := Prompt(tt.prompt, tt.maxSize)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("Prompt(len=%d, max=%d) = %v, want nil", len(tt.prompt), tt.maxSize, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("Prompt(len=%d, max=%d) = %v, want %v", len(tt.prompt), tt.maxSize, err, tt.wantErr)
				}
			}
		})
	}
}

func TestModel(t *testing.T) {
	allowlist := []string{"opus", "sonnet", "haiku"}

	tests := []struct {
		name      string
		model     string
		allowlist []string
		wantErr   error
	}{
		{"allowed model", "opus", allowlist, nil},
		{"allowed case insensitive", "OPUS", allowlist, nil},
		{"allowed with whitespace", "  sonnet  ", allowlist, nil},
		{"not allowed", "gpt-4", allowlist, ErrModelNotAllowed},
		{"empty allowlist allows all", "anything", nil, nil},
		{"empty allowlist allows all 2", "whatever", []string{}, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := Model(tt.model, tt.allowlist)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("Model(%q, %v) = %v, want nil", tt.model, tt.allowlist, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("Model(%q, %v) = %v, want %v", tt.model, tt.allowlist, err, tt.wantErr)
				}
			}
		})
	}
}

func TestBinary(t *testing.T) {
	tests := []struct {
		name    string
		binary  string
		wantErr error
	}{
		{"allowed claude", "claude", nil},
		{"allowed codex", "codex", nil},
		{"allowed with path", "/usr/local/bin/claude", nil},
		{"not allowed", "bash", ErrBinaryNotAllowed},
		{"not allowed python", "python", ErrBinaryNotAllowed},
		{"empty", "", ErrBinaryNotAllowed},
		{"case insensitive", "CLAUDE", nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := Binary(tt.binary)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("Binary(%q) = %v, want nil", tt.binary, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("Binary(%q) = %v, want %v", tt.binary, err, tt.wantErr)
				}
			}
		})
	}
}

func TestProviderName(t *testing.T) {
	tests := []struct {
		name    string
		pname   string
		wantErr error
	}{
		{"valid simple", "claude", nil},
		{"valid with hyphen", "claude-code", nil},
		{"valid with numbers", "claude2", nil},
		{"valid long", "a" + strings.Repeat("b", 63), nil},
		{"empty", "", ErrProviderNameInvalid},
		{"starts with number", "1claude", ErrProviderNameInvalid},
		{"starts with hyphen", "-claude", ErrProviderNameInvalid},
		{"uppercase", "Claude", ErrProviderNameInvalid},
		{"underscore", "claude_code", ErrProviderNameInvalid},
		{"too long", "a" + strings.Repeat("b", 64), ErrProviderNameInvalid},
		{"special chars", "claude!", ErrProviderNameInvalid},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ProviderName(tt.pname)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("ProviderName(%q) = %v, want nil", tt.pname, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("ProviderName(%q) = %v, want %v", tt.pname, err, tt.wantErr)
				}
			}
		})
	}
}

func TestEnv(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		wantErr error
	}{
		{"nil map", nil, nil},
		{"empty map", map[string]string{}, nil},
		{"valid env", map[string]string{"FOO": "bar", "BAZ": "qux"}, nil},
		{"blocked key", map[string]string{"PATH": "/bin"}, ErrEnvValueBlocked},
		{"invalid key", map[string]string{"FOO\x00BAR": "value"}, ErrEnvKeyInvalid},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := Env(tt.env)
			if tt.wantErr == nil {
				if err != nil {
					t.Errorf("Env(%v) = %v, want nil", tt.env, err)
				}
			} else {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("Env(%v) = %v, want %v", tt.env, err, tt.wantErr)
				}
			}
		})
	}
}

func TestDefaultModelLists(t *testing.T) {
	// Test that default model lists are usable
	if len(DefaultClaudeModels) == 0 {
		t.Error("DefaultClaudeModels is empty")
	}
	if len(DefaultCodexModels) == 0 {
		t.Error("DefaultCodexModels is empty")
	}

	// Verify opus is in Claude models
	if err := Model("opus", DefaultClaudeModels); err != nil {
		t.Errorf("opus should be in DefaultClaudeModels: %v", err)
	}

	// Verify gpt-5.2-codex is in Codex models
	if err := Model("gpt-5.2-codex", DefaultCodexModels); err != nil {
		t.Errorf("gpt-5.2-codex should be in DefaultCodexModels: %v", err)
	}
}

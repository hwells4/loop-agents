package provider

import (
	"errors"
	"sort"
	"strings"
	"sync"
)

var (
	// ErrProviderExists indicates a provider is already registered.
	ErrProviderExists = errors.New("provider already registered")
	// ErrProviderNotFound indicates the provider name is unknown.
	ErrProviderNotFound = errors.New("provider not found")
)

// Registry tracks available providers by canonical name.
type Registry struct {
	mu        sync.RWMutex
	providers map[string]Provider
}

// NewRegistry returns an empty provider registry.
func NewRegistry() *Registry {
	return &Registry{providers: make(map[string]Provider)}
}

// Register adds a provider to the registry under its canonical name.
func (r *Registry) Register(p Provider) error {
	if p == nil {
		return errors.New("provider is nil")
	}
	name := NormalizeName(p.Name())
	if name == "" {
		return errors.New("provider name is empty")
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.providers[name]; ok {
		return ErrProviderExists
	}
	r.providers[name] = p
	return nil
}

// Get returns the provider registered for name or false if missing.
func (r *Registry) Get(name string) (Provider, bool) {
	canonical := NormalizeName(name)
	if canonical == "" {
		return nil, false
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	p, ok := r.providers[canonical]
	return p, ok
}

// Names returns all registered provider names in sorted order.
func (r *Registry) Names() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	names := make([]string, 0, len(r.providers))
	for name := range r.providers {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

var defaultRegistry = NewRegistry()

// Register adds a provider to the default registry.
func Register(p Provider) error {
	return defaultRegistry.Register(p)
}

// Get fetches a provider from the default registry.
func Get(name string) (Provider, bool) {
	return defaultRegistry.Get(name)
}

// Names returns the provider names from the default registry.
func Names() []string {
	return defaultRegistry.Names()
}

// NormalizeName maps provider aliases to canonical names.
func NormalizeName(name string) string {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "claude", "claude-code", "anthropic":
		return "claude"
	case "codex", "openai":
		return "codex"
	default:
		return strings.ToLower(strings.TrimSpace(name))
	}
}

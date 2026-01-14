#!/bin/bash
# Dependency checks for agent pipelines

DEPS_CHECKED_BASE=""

print_install_instructions() {
  local tool=$1
  local os=""

  os=$(uname -s 2>/dev/null || echo "")

  case "$tool" in
    jq)
      echo "  Install jq:" >&2
      case "$os" in
        Darwin)
          echo "    brew install jq" >&2
          ;;
        *)
          if command -v apt-get >/dev/null 2>&1; then
            echo "    sudo apt-get update && sudo apt-get install -y jq" >&2
          elif command -v dnf >/dev/null 2>&1; then
            echo "    sudo dnf install -y jq" >&2
          elif command -v yum >/dev/null 2>&1; then
            echo "    sudo yum install -y jq" >&2
          else
            echo "    https://stedolan.github.io/jq/download/" >&2
          fi
          ;;
      esac
      ;;
    yq)
      echo "  Install yq (Go-based v4+):" >&2
      case "$os" in
        Darwin)
          echo "    brew install yq" >&2
          ;;
        *)
          if command -v snap >/dev/null 2>&1; then
            echo "    sudo snap install yq" >&2
          else
            echo "    https://github.com/mikefarah/yq#install" >&2
          fi
          ;;
      esac
      ;;
    tmux)
      echo "  Install tmux:" >&2
      case "$os" in
        Darwin)
          echo "    brew install tmux" >&2
          ;;
        *)
          if command -v apt-get >/dev/null 2>&1; then
            echo "    sudo apt-get update && sudo apt-get install -y tmux" >&2
          elif command -v dnf >/dev/null 2>&1; then
            echo "    sudo dnf install -y tmux" >&2
          elif command -v yum >/dev/null 2>&1; then
            echo "    sudo yum install -y tmux" >&2
          else
            echo "    https://github.com/tmux/tmux/wiki/Installing" >&2
          fi
          ;;
      esac
      ;;
    bd)
      echo "  Install beads CLI (bd):" >&2
      echo "    https://github.com/hwells4/beads" >&2
      ;;
    *)
      ;;
  esac
}

check_jq_version() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: Missing required command: jq" >&2
    print_install_instructions "jq"
    return 1
  fi

  local version_output=""
  version_output=$(jq --version 2>/dev/null || true)
  if [[ ! "$version_output" =~ ([0-9]+)\.([0-9]+) ]]; then
    echo "Error: Unable to parse jq version: $version_output" >&2
    print_install_instructions "jq"
    return 1
  fi

  local major=${BASH_REMATCH[1]}
  local minor=${BASH_REMATCH[2]}

  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 6 ]; }; then
    echo "Error: jq 1.6+ required (found $version_output)" >&2
    print_install_instructions "jq"
    return 1
  fi

  return 0
}

check_yq_version() {
  if ! command -v yq >/dev/null 2>&1; then
    echo "Error: Missing required command: yq (Go-based v4+)" >&2
    print_install_instructions "yq"
    return 1
  fi

  local version_output=""
  version_output=$(yq --version 2>/dev/null || true)
  if [[ ! "$version_output" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    if [[ "$version_output" =~ ([0-9]+)\.([0-9]+) ]]; then
      local major=${BASH_REMATCH[1]}
      if [ "$major" -lt 4 ]; then
        echo "Error: yq v4+ required (found $version_output)" >&2
        echo "  Detected Python yq; install Mike Farah's Go-based yq v4." >&2
        print_install_instructions "yq"
        return 1
      fi
      return 0
    fi
    echo "Error: Unable to parse yq version: $version_output" >&2
    print_install_instructions "yq"
    return 1
  fi

  local major=${BASH_REMATCH[1]}

  if [ "$major" -lt 4 ]; then
    echo "Error: yq v4+ required (found $version_output)" >&2
    echo "  Detected Python yq; install Mike Farah's Go-based yq v4." >&2
    print_install_instructions "yq"
    return 1
  fi

  return 0
}

check_deps() {
  local require_tmux=${PIPELINE_TMUX_REQUIRED:-""}
  local require_bd=""

  if [ -n "${TMUX:-}" ]; then
    require_tmux="true"
  fi

  for arg in "$@"; do
    case "$arg" in
      --require-tmux) require_tmux="true" ;;
      --require-bd) require_bd="true" ;;
    esac
  done

  if [ -z "$DEPS_CHECKED_BASE" ]; then
    check_jq_version || return 1
    check_yq_version || return 1
    DEPS_CHECKED_BASE="true"
  fi

  if [ "$require_tmux" = "true" ]; then
    if ! command -v tmux >/dev/null 2>&1; then
      echo "Error: Missing required command: tmux" >&2
      print_install_instructions "tmux"
      return 1
    fi
  fi

  if [ "$require_bd" = "true" ]; then
    if ! command -v bd >/dev/null 2>&1; then
      echo "Error: Missing required command: bd (beads CLI)" >&2
      print_install_instructions "bd"
      return 1
    fi
  fi

  return 0
}

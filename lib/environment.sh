#!/bin/bash

# Definitions only; em_init_environment configures defaults explicitly.
# Exports use the logging helpers from shell.sh.

# Create missing parent directories using arguments supported by macOS and Linux.
em_mkdir() {
  command mkdir -p "$@"
}

em_get_var_value() {
  # Only a variable identifier is interpolated into eval; the value is data.
  case "$1" in
    ''|[0-9]*|*[!a-zA-Z0-9_]*) return 2 ;;
  esac
  eval 'printf "%s\n" "${'"$1"'-}"'
}

# Print the first nonempty value, or an empty line when none is available.
em_first_nonempty() {
  local alternative
  for alternative in "$@"; do
    if [ -n "$alternative" ]; then
      printf '%s\n' "$alternative"
      return
    fi
  done
  printf '\n'
}

em_export_alternatives() {
  local var_name="$1"
  shift  # Remove variable name from arguments

  local original_value
  original_value="$(em_get_var_value "$var_name")" || return

  # Return immediately if variable is already set
  if [ -n "$original_value" ]; then
    em_print_debug '%s is already set\n' "$var_name"
    return
  fi

  # No alternatives provided - exit early
  if [ $# -eq 0 ]; then
    return
  fi
  local selected_value
  selected_value="$(em_first_nonempty "$@")"

  # Export the final value
  export "$var_name"="$selected_value"

  em_print 'Configured %s\n' "$var_name"
}

# Configure defaults and create the fallback temporary directory.
em_init_environment() {
  if [ -z "$TMPDIR" ]; then
    if [ -n "$HOME" ]; then
      # If HOME is set, use a subdirectory under it for temporary files.
      TMPDIR="$HOME/.tmp"
      em_mkdir "$TMPDIR"
    else
      # Fallback to /tmp if HOME is not set.
      TMPDIR="/tmp"
    fi

    export TMPDIR
  fi

  ENVMANAGER_SYSTEMD_IDENTIFIER=envmanager
  ENVMANAGER_VERSION="0.0.1"
  ENVMANAGER_ENABLE_LOGGING="${ENVMANAGER_ENABLE_LOGGING:-false}"

  # Default interval before a throttled command may run again.
  # Override per-call with a leading duration arg (1d, 12h, 30m, 90s) or a bare seconds count.
  ENVMANAGER_RUN_EVERY_DEFAULT="${ENVMANAGER_RUN_EVERY_DEFAULT:-86400}" # 1 day
}

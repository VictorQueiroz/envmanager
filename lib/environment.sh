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

# Preserve an explicit path, otherwise reuse the first existing path (preferred
# first), falling back to the preferred path for a new installation. Paths may
# name directories or files; selection never creates or migrates either.
em_export_path() {
  [ $# -ge 2 ] && [ -n "$2" ] || return 2
  local var_name="$1" preferred_path="$2" original_value selected_path candidate
  shift 2
  original_value="$(em_get_var_value "$var_name")" || return
  if [ -n "$original_value" ]; then
    export "$var_name=$original_value"
    return 0
  fi

  selected_path="$preferred_path"
  for candidate in "$preferred_path" "$@"; do
    if [ -n "$candidate" ] && [ -e "$candidate" ]; then
      selected_path="$candidate"
      break
    fi
  done
  export "$var_name=$selected_path"
  em_print 'Configured %s\n' "$var_name"
}

# Add one literal entry to a colon-separated search path. Existing entries keep
# their position unless prepend-move is requested; preserve all other fields.
em_add_path() {
  [ $# -ge 2 ] && [ $# -le 3 ] && [ -n "$2" ] || return 2
  case "$1" in
    ''|[0-9]*|*[!a-zA-Z0-9_]*) return 2 ;;
  esac
  case "$2" in *:*) return 2 ;; esac
  local _em_path_name="$1" _em_path_entry="$2" _em_path_mode="${3-append}"
  local _em_path_value _em_path_remaining _em_path_component
  case "$_em_path_mode" in
    append|prepend|prepend-move) ;;
    *) return 2 ;;
  esac

  # Only the validated identifier is evaluated; path values remain literal data.
  eval '_em_path_value="${'"$_em_path_name"'-}"'
  if [ "$_em_path_mode" != prepend-move ]; then
    case ":$_em_path_value:" in
      *":$_em_path_entry:"*)
        export "$_em_path_name=$_em_path_value"
        return
        ;;
    esac
  fi

  if [ -z "$_em_path_value" ]; then
    # Empty MANPATH means the system's default search path. Keep that implicit
    # entry on the appropriate side instead of replacing the defaults.
    case "$_em_path_name:$_em_path_mode" in
      MANPATH:append) _em_path_value=":$_em_path_entry" ;;
      MANPATH:*) _em_path_value="$_em_path_entry:" ;;
      *) _em_path_value="$_em_path_entry" ;;
    esac
  else
    case "$_em_path_mode" in
      append) _em_path_value="$_em_path_value:$_em_path_entry" ;;
      prepend) _em_path_value="$_em_path_entry:$_em_path_value" ;;
      prepend-move)
        _em_path_remaining="$_em_path_value"
        _em_path_value="$_em_path_entry"
        while :; do
          _em_path_component="${_em_path_remaining%%:*}"
          if [ "$_em_path_component" != "$_em_path_entry" ]; then
            _em_path_value="$_em_path_value:$_em_path_component"
          fi
          case "$_em_path_remaining" in
            *:*) _em_path_remaining="${_em_path_remaining#*:}" ;;
            *) break ;;
          esac
        done
        ;;
    esac
  fi
  export "$_em_path_name=$_em_path_value"
}

# Configure defaults and create the fallback temporary directory.
em_init_environment() {
  local os runtime
  os="$(em_current_os)" || return
  runtime="$(em_current_runtime)" || return
  if [ "$os" = android ]; then
    if [ -z "${TMPDIR:-}" ]; then
      if [ "$runtime" = termux ] && [ -n "${PREFIX:-}" ]; then
        TMPDIR="$PREFIX/tmp"
      elif [ -n "${HOME:-}" ]; then
        TMPDIR="$HOME/.tmp"
      else
        printf 'envmanager: Android requires a writable TMPDIR or HOME\n' >&2
        return 1
      fi
    fi
    case "$TMPDIR" in
      /*) ;;
      *) printf 'envmanager: Android TMPDIR must be absolute\n' >&2; return 1 ;;
    esac
    em_mkdir "$TMPDIR" || return
    [ -d "$TMPDIR" ] && [ -w "$TMPDIR" ] && [ -x "$TMPDIR" ] || {
      printf 'envmanager: Android TMPDIR is not writable: %s\n' "$TMPDIR" >&2
      return 1
    }
    export TMPDIR
  fi
  if [ -z "$TMPDIR" ]; then
    if [ -n "$HOME" ]; then
      # If HOME is set, use a subdirectory under it for temporary files.
      TMPDIR="$HOME/.tmp"
      em_mkdir "$TMPDIR" || return
    else
      # Fallback to /tmp if HOME is not set.
      TMPDIR="/tmp"
    fi

    export TMPDIR
  fi

  # Providers may need these before the numbered defaults script is loaded.
  if [ -n "${HOME:-}" ]; then
    em_export_alternatives XDG_CONFIG_HOME "$HOME/.config"
    em_export_alternatives XDG_CACHE_HOME "$HOME/.cache"
    em_export_alternatives XDG_DATA_HOME "$HOME/.local/share"
    em_export_alternatives XDG_STATE_HOME "$HOME/.local/state"
  fi

  ENVMANAGER_SYSTEMD_IDENTIFIER=envmanager
  ENVMANAGER_VERSION="0.0.1"
  ENVMANAGER_ENABLE_LOGGING="${ENVMANAGER_ENABLE_LOGGING:-false}"

  # Default interval before a throttled command may run again.
  # Override per-call with a leading duration arg (1d, 12h, 30m, 90s) or a bare seconds count.
  ENVMANAGER_RUN_EVERY_DEFAULT="${ENVMANAGER_RUN_EVERY_DEFAULT:-86400}" # 1 day
}

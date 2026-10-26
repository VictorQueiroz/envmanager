#!/bin/bash

# Definitions only. Persistence uses em_mkdir from environment.sh.

# Discover only top-level regular scripts, preserving the existing load order.
em_script_files() {
  find "$ENVMANAGER_DIR" -maxdepth 1 -name '*.sh' -type f -print | sort
}

# Numeric ordering, OS qualifiers and local overrides share one public name.
em_script_name() {
  local name="${1##*/}" prefix
  name="${name%.sh}"
  name="${name%.local}"
  case "$name" in
    *.android.termux|*.android.system) name="${name%.*}" ;;
  esac
  case "$name" in
    *.android|*.linux|*.macos|*.darwin|*.freebsd|*.openbsd|*.netbsd|*.windows)
      name="${name%.*}" ;;
  esac
  prefix="${name%%-*}"
  case "$prefix" in
    ''|*[!0-9]*) ;;
    *) name="${name#*-}" ;;
  esac
  printf '%s\n' "$name"
}

em_script_os() {
  local name="${1##*/}"
  name="${name%.sh}"
  name="${name%.local}"
  case "$name" in
    *.android|*.android.termux|*.android.system) printf 'android\n' ;;
    *.macos|*.darwin) printf 'macos\n' ;;
    *.linux|*.freebsd|*.openbsd|*.netbsd|*.windows) printf '%s\n' "${name##*.}" ;;
  esac
}

em_script_runtime() {
  local name="${1##*/}"
  name="${name%.sh}"
  name="${name%.local}"
  case "$name" in
    *.android.termux|*.android.system) printf '%s\n' "${name##*.}" ;;
  esac
}

# Return a reason without sourcing the script or invoking its installer.
em_script_unsupported_reason() {
  local name script_os script_runtime os runtime
  name="$(em_script_name "$1")"
  script_os="$(em_script_os "$1")"
  script_runtime="$(em_script_runtime "$1")"
  if em_platform_cache_valid; then
    os="$_EM_PLATFORM_OS"
    runtime="$_EM_PLATFORM_RUNTIME"
  else
    os="$(em_current_os)" || return
    runtime="$(em_current_runtime)" || return
  fi
  if [ -n "$script_os" ] && [ "$script_os" != "$os" ]; then
    printf 'requires OS %s\n' "$script_os"
    return
  fi
  if [ -n "$script_runtime" ] && [ "$script_runtime" != "$runtime" ]; then
    printf 'requires runtime %s\n' "$script_runtime"
    return
  fi
  if [ "$os" = android ] && [ -z "$script_os" ]; then
    case "$name" in
      python|nvm|sdkman|wasi|emsdk|pnpm|doppler|tmux|default-browser|cursor)
        printf 'desktop installer; use an Android provider\n'; return ;;
    esac
    case "$name" in
      defaults|disable-telemetry|docker|home-bin-folders|gradle|keras|rust|codex|claude-code|nextjs|npm|nodejs|openwiki|model-context-protocol|playwright|turborepo) ;;
      editor|tmpdir)
        if [ "$runtime" != termux ] || [ -z "${BASH_VERSION:-}${ZSH_VERSION:-}" ]; then
          printf 'requires Termux with Bash or Zsh\n'; return
        fi ;;
      *) printf 'requires an audited Android script or explicit Android suffix\n'; return ;;
    esac
  fi
  if [ "$name" = wasi ] && [ -z "$script_os" ]; then
    if [ "$os" != linux ] || [ "$(em_current_arch)" != x86_64 ]; then
      printf 'requires Linux x86_64 binaries\n'
    fi
  fi
  return 0
}

em_script_supported() {
  local reason
  reason="$(em_script_unsupported_reason "$1")" || return
  [ -z "$reason" ]
}

em_disabled_file() {
  printf '%s\n' "${ENVMANAGER_DISABLED_FILE:-$ENVMANAGER_DIR/disabled-scripts}"
}

em_is_disabled() {
  local name="$1" disabled_file line
  disabled_file="$(em_disabled_file)"
  [ -f "$disabled_file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$name" ] && return 0
  done < "$disabled_file"
  return 1
}

em_disabled_scripts() {
  local disabled_file line
  disabled_file="$(em_disabled_file)"
  [ -f "$disabled_file" ] || return 0
  [ -r "$disabled_file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    printf '%s\n' "$line"
  done < "$disabled_file" | sort -u
}

# Split a sorted snapshot without a subshell, word splitting, or heredocs.
# Android mksh may place heredoc files in an inaccessible system directory.
em_each_script() {
  local files file
  files="$(em_script_files)" || return
  while [ -n "$files" ]; do
    file="${files%%"
"*}"
    if [ "$files" = "$file" ]; then
      files=""
    else
      files="${files#*"
"}"
    fi
    [ -n "$file" ] || continue
    "$@" "$file" || return
  done
}

em_print_script_name() {
  local name
  name="$(em_script_name "$1")"
  [ "$name" = core ] || printf '%s\n' "$name"
  return 0
}

em_script_names() {
  em_each_script em_print_script_name | sort -u
}

em_print_available_script_name() {
  em_script_supported "$1" || return 0
  em_print_script_name "$1"
}

# Use the same compatibility policy for loading and completion suggestions.
em_available_script_names() {
  em_with_platform em_each_script em_print_available_script_name | sort -u
}

em_script_exists() {
  local names
  [ -n "$1" ] || return 1
  names="$(em_script_names)" || return
  case "
$names
" in
    *"
$1
"*) return 0 ;;
  esac
  return 1
}

# Persist short names; disabling affects future loads, including local variants.
# With no arguments, print the current blacklist.
em_disable() {
  [ "$#" -gt 0 ] || { em_disabled_scripts; return; }
  local name disabled_file disabled_directory disabled_names temporary_file
  for name in "$@"; do
    if ! em_script_exists "$name"; then
      printf 'em_disable: unknown or protected script: %s\n' "$name" >&2
      return 2
    fi
  done

  disabled_file="$(em_disabled_file)"
  if [ -d "$disabled_file" ]; then
    printf 'em_disable: blacklist path is a directory: %s\n' "$disabled_file" >&2
    return 1
  fi
  case "$disabled_file" in
    */*) disabled_directory="${disabled_file%/*}"
         disabled_directory="${disabled_directory:-/}" ;;
    *) disabled_directory=. ;;
  esac
  disabled_names="$(em_disabled_scripts)" || return
  em_mkdir "$disabled_directory" || return
  temporary_file="$(mktemp "$disabled_file.XXXXXX")" || return
  if ! {
    [ -z "$disabled_names" ] || printf '%s\n' "$disabled_names"
    printf '%s\n' "$@"
  } | sort -u > "$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  if ! mv -f "$temporary_file" "$disabled_file"; then
    rm -f "$temporary_file"
    return 1
  fi
}

# Remove disabled names; scripts run only on a subsequent load.
# Existing disabled entries can be removed even if their scripts are gone.
em_enable() {
  [ "$#" -gt 0 ] || { em_disabled_scripts; return; }
  local disabled_file name requested_name needs_update=false
  disabled_file="$(em_disabled_file)"
  if [ -d "$disabled_file" ]; then
    printf 'em_enable: blacklist path is a directory: %s\n' "$disabled_file" >&2
    return 1
  fi
  if [ -f "$disabled_file" ] && [ ! -r "$disabled_file" ]; then
    printf 'em_enable: cannot read blacklist: %s\n' "$disabled_file" >&2
    return 1
  fi

  # Validate the whole request before changing the file.
  for name in "$@"; do
    if em_is_disabled "$name"; then
      needs_update=true
    elif ! em_script_exists "$name"; then
      printf 'em_enable: unknown or protected script: %s\n' "$name" >&2
      return 2
    fi
  done
  [ "$needs_update" = true ] || return 0

  local remaining_names="" remove_name temporary_file
  while IFS= read -r name || [ -n "$name" ]; do
    remove_name=false
    for requested_name in "$@"; do
      if [ "$name" = "$requested_name" ]; then
        remove_name=true
        break
      fi
    done
    if [ "$remove_name" = false ]; then
      remaining_names="$remaining_names$name
"
    fi
  done < "$disabled_file" || return

  temporary_file="$(mktemp "$disabled_file.XXXXXX")" || return
  if ! printf '%s' "$remaining_names" > "$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  if ! mv -f "$temporary_file" "$disabled_file"; then
    rm -f "$temporary_file"
    return 1
  fi
}

em_should_load() {
  local name
  name="$(em_script_name "$1")"
  em_is_disabled "$name" && return 1
  em_script_supported "$1"
}

em_load_script() {
  [ "$1" = "$ENVMANAGER_DIR/00-core.sh" ] && return 0
  em_should_load "$1" || return 0
  . "$1"
}

em_load_scripts() {
  em_with_platform em_each_script em_load_script
}

em_script_status() {
  local name reason
  name="$(em_script_name "$1")"
  [ "$name" = core ] && return 0
  reason="$(em_script_unsupported_reason "$1")" || return
  if [ -n "$reason" ]; then
    printf '%s: unsupported (%s)' "${1##*/}" "$reason"
    if em_is_disabled "$name"; then printf '; disabled'; fi
    printf '\n'
  elif em_is_disabled "$name"; then
    printf '%s: disabled\n' "${1##*/}"
  else
    printf '%s: enabled\n' "${1##*/}"
  fi
}

# Inspect compatibility and user choices without executing feature scripts.
em_status() {
  em_platform || return
  em_each_script em_script_status
}

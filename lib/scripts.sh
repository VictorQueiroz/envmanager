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
    *.linux|*.macos|*.darwin|*.freebsd|*.openbsd|*.netbsd|*.windows)
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
    *.macos|*.darwin) printf 'macos\n' ;;
    *.linux|*.freebsd|*.openbsd|*.netbsd|*.windows) printf '%s\n' "${name##*.}" ;;
  esac
}

# Normalize an observed OS name without querying the host.
em_normalize_os() {
  case "$1" in
    Darwin) printf 'macos\n' ;;
    CYGWIN*|MINGW*|MSYS*) printf 'windows\n' ;;
    *) printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

em_current_os() {
  local os
  os="$(uname -s)" || return
  em_normalize_os "$os"
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

em_script_names() {
  local file name
  while IFS= read -r file; do
    name="$(em_script_name "$file")"
    [ "$name" = core ] || printf '%s\n' "$name"
  done < <(em_script_files) | sort -u
}

# Completion candidates need at least one generic or current-OS script variant.
# Keep em_script_names unfiltered so explicit commands can manage other OSes.
em_available_script_names() {
  local file name script_os current_os
  current_os="$(em_current_os)" || return
  while IFS= read -r file; do
    script_os="$(em_script_os "$file")"
    [ -z "$script_os" ] || [ "$script_os" = "$current_os" ] || continue
    name="$(em_script_name "$file")"
    [ "$name" = core ] || printf '%s\n' "$name"
  done < <(em_script_files) | sort -u
}

em_script_exists() {
  local name
  while IFS= read -r name; do
    [ "$name" = "$1" ] && return 0
  done < <(em_script_names)
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
      remaining_names="$remaining_names$name"$'\n'
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
  local name script_os current_os
  name="$(em_script_name "$1")"
  em_is_disabled "$name" && return 1
  script_os="$(em_script_os "$1")"
  if [ -n "$script_os" ]; then
    current_os="$(em_current_os)" || return 1
    [ "$script_os" = "$current_os" ] || return 1
  fi
  return 0
}

em_load_scripts() {
  local file
  while IFS= read -r file; do
    [ "$file" = "$ENVMANAGER_DIR/00-core.sh" ] && continue
    em_should_load "$file" || continue
    source "$file"
  done < <(em_script_files)
}

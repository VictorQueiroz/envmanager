#!/bin/bash

ENVMANAGER_SYSTEMD_IDENTIFIER=envmanager
ENVMANAGER_VERSION="0.0.1"
ENVMANAGER_ENABLE_LOGGING="${ENVMANAGER_ENABLE_LOGGING:-false}"

em_systemd-cat() {
  if [ "$ENVMANAGER_ENABLE_LOGGING" != "true" ]; then
    return
  fi
  systemd-cat --stderr-priority=err --identifier="$ENVMANAGER_SYSTEMD_IDENTIFIER" "$@"
}
  

em_print_debug() {
  em_systemd-cat --priority=debug printf "$@"
}

em_print_err() {
  em_systemd-cat --priority=err printf "$@"
}

em_print() {
  em_print_debug "$@"
}

em_get_var_value() {
    var_name="$1"
    # Try bash/zsh method first
    if value=$(eval "echo \"\${$var_name}\"" 2>/dev/null); then
        echo "$value"
    else
        # POSIX-compliant fallback
        eval "echo \"\${$var_name}\""
    fi
}

em_export_alternatives() {
  local var_name="$1"
  shift  # Remove variable name from arguments

  local original_value
  original_value="$(em_get_var_value "${var_name}")"
  
  # Return immediately if variable is already set
  if [ -n "$original_value" ]; then
    em_print_debug '%s is already set: %s\n' "$var_name" "$original_value"
    return
  fi
  
  # No alternatives provided - exit early
  if [ $# -eq 0 ]; then
    return
  fi
  
  local selected_value=""
  local last_alt

  # Process alternatives in order
  for alt in "$@"; do
    # Always remember the last alternative
    last_alt="$alt"
    # Use first non-empty alternative found
    if [ -n "$alt" ]; then
      selected_value="$alt"
      break
    fi
  done
  
  # If no non-empty alternative found, use last alternative (even if empty)
  if [ -z "$selected_value" ]; then
    selected_value="$last_alt"
  fi
  
  # Export the final value
  export "$var_name"="$selected_value"

  em_print '%s=%s\n' "$var_name" "$selected_value"
}

# Default interval before a throttled command may run again.
# Override per-call with a leading duration arg (1d, 12h, 30m, 90s) or a bare seconds count.
ENVMANAGER_RUN_EVERY_DEFAULT="${ENVMANAGER_RUN_EVERY_DEFAULT:-86400}" # 1 day

# Hash a string into a short, filesystem-safe token.
em_hash() {
  if command -v sha1sum &>/dev/null; then
    printf '%s' "$1" | sha1sum | cut -d' ' -f1
  elif command -v md5sum &>/dev/null; then
    printf '%s' "$1" | md5sum | cut -d' ' -f1
  else
    printf '%s' "$1" | cksum | tr -d ' '
  fi
}

# Convert a human duration (1d/12h/30m/90s, or bare seconds) into seconds.
em_duration_to_seconds() {
  case "$1" in
    *d) printf '%s' "$(( ${1%d} * 86400 ))" ;;
    *h) printf '%s' "$(( ${1%h} * 3600 ))" ;;
    *m) printf '%s' "$(( ${1%m} * 60 ))" ;;
    *s) printf '%s' "$(( ${1%s} ))" ;;
    *)  printf '%s' "$1" ;;
  esac
}

# Run a command at most once per interval, persisting an expiration epoch under $TMPDIR.
#
# Usage:
#   em_run_every <command...>             # uses ENVMANAGER_RUN_EVERY_DEFAULT
#   em_run_every <interval> <command...>  # e.g. em_run_every 7d git -C "$EMSDK_DIR" pull
#
# The expiration is refreshed only when the command succeeds, so a failed run
# (e.g. an offline `git pull`) is retried next shell instead of being skipped.
em_run_every() {
  local interval="$ENVMANAGER_RUN_EVERY_DEFAULT"

  # Treat the first arg as an interval only if it looks like one and a command follows.
  # Uses POSIX parameter expansion + case so it behaves identically in Bash and Zsh
  # (the previous `<->` patterns were Zsh-only numeric globs and never matched in Bash).
  case "${1%[dhms]}" in
    ''|*[!0-9]*) ;;                                   # not an interval, keep default
    *) [ "$#" -gt 1 ] && { interval="$1"; shift; } ;; # bare digits or N[dhms]
  esac

  if [ "$#" -eq 0 ]; then
    em_print_err 'em_run_every: no command given\n'
    return 2
  fi

  local ttl now state_dir state_file expiry
  ttl="$(em_duration_to_seconds "$interval")"
  now="$(date +%s)"
  state_dir="$TMPDIR/envmanager/run-every"
  state_file="$state_dir/$(em_hash "$*")"

  if [ -f "$state_file" ]; then
    read -r expiry < "$state_file"
    if [ -n "$expiry" ] && [ "$now" -lt "$expiry" ]; then
      em_print_debug 'em_run_every: skip (%ss left): %s\n' "$(( expiry - now ))" "$*"
      return 0
    fi
  fi

  em_print_debug 'em_run_every: running: %s\n' "$*"
  "$@" || return $?

  mkdir --parents "$state_dir"
  printf '%s\n' "$(( now + ttl ))" > "$state_file"
}

# zsh-snap (`znap`) provides lazy command loading in Zsh. In Bash — or any shell
# without zsh-snap — provide a minimal shim so the same rc scripts work in both.
# Only the `znap function <loader> <trigger> <snippet>` form is used here.
if ! command -v znap >/dev/null 2>&1; then
  znap() {
    [ "$1" = function ] || return 0
    # $2 = loader name (Zsh completion only, ignored here)
    # $3 = trigger command, $4 = snippet that installs the real command
    local trigger="$3" snippet="$4"
    eval "${trigger}() {
      unset -f ${trigger}   # remove the stub
      ${snippet}            # install the real command (defines ${trigger})
      ${trigger} \"\$@\"    # re-dispatch to it
    }"
  }

  # Zsh completion registration — no Bash equivalent needed.
  compdef() { :; }
fi

em_print 'Configuring EnvManager... Old environment below:\n'
em_print '---\n'
em_print '%s' "$(env)"
em_print '---\n'

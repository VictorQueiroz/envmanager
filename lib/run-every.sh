#!/bin/bash

# Definitions only. Uses em_mkdir and the logging helpers.

# Clock boundary; callers can supply a deterministic clock by redefining it.
em_now() {
  date +%s
}

# Return success while an expiration is still in the future. Empty means due.
em_expiry_pending() {
  [ -n "$2" ] && [ "$1" -lt "$2" ]
}

# Hash a string into a short, filesystem-safe token.
em_hash() {
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha1sum | cut -d' ' -f1
  elif command -v md5sum >/dev/null 2>&1; then
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
  now="$(em_now)"
  state_dir="$TMPDIR/envmanager/run-every"
  state_file="$state_dir/$(em_hash "$*")"

  if [ -f "$state_file" ]; then
    read -r expiry < "$state_file"
    if em_expiry_pending "$now" "$expiry"; then
      em_print_debug 'em_run_every: skip (%ss left)\n' "$(( expiry - now ))"
      return 0
    fi
  fi

  em_print_debug 'em_run_every: running\n'
  "$@" || return $?

  em_mkdir "$state_dir" || return
  printf '%s\n' "$(( now + ttl ))" > "$state_file"
}

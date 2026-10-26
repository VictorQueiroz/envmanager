# Cross-session concurrency limits. Imports only define functions.
# Uses local filesystem operations, SHA-256, mktemp, and standard shell utilities.

em_concurrency_available() {
  [ "$1" -lt "$2" ]
}

_em_concurrent_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    command sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    command shasum -a 256
  else
    printf '%s\n' 'em_run_concurrent: sha256sum or shasum is required' >&2
    return 127
  fi
}

_em_concurrent_precedes() {
  local first
  first="$(printf '%s\n%s\n' "${1##*/}" "${2##*/}" | LC_ALL=C command sort | command head -n 1)" || return
  [ "$first" = "${1##*/}" ]
}

_em_concurrent_alive() {
  local request="$1" owner worker
  owner="${request##*/}"
  owner="${owner%%.*}"
  if kill -0 "$owner" 2>/dev/null; then
    return 0
  fi
  # A command may outlive the shell that invoked the prefix.
  if [ -f "$request/worker" ]; then
    { IFS= read -r worker < "$request/worker"; } 2>/dev/null || return 1
    kill -0 "$worker" 2>/dev/null && return 0
  fi
  return 1
}

_em_concurrent_cleanup() {
  # Each invocation owns a unique directory; no reusable lock is unlinked.
  [ -z "$em_concurrent_probe" ] || command rm -f "$em_concurrent_probe"
  [ -n "$em_concurrent_request" ] || return 0
  if [ -n "$em_concurrent_worker" ] && kill -0 "$em_concurrent_worker" 2>/dev/null; then
    return 0
  fi
  command rm -rf "$em_concurrent_request"
}

em_run_concurrent() (
  # A subshell isolates traps/options and also gives every invocation its own PID.
  local em_concurrent_key= em_concurrent_keyed=false em_concurrent_limit
  local em_concurrent_root em_concurrent_hash em_concurrent_owner em_concurrent_probe=
  local em_concurrent_request= em_concurrent_worker= em_concurrent_result
  local em_concurrent_other em_concurrent_ticket em_concurrent_max=0
  local em_concurrent_number em_concurrent_before em_concurrent_choosing
  local em_concurrent_shell_flags="$-"
  local em_concurrent_globignore="${GLOBIGNORE-}" em_concurrent_globignore_set="${GLOBIGNORE+x}"
  local GLOBIGNORE=
  # Caller glob settings must not hide competing requests. Restore them for
  # the command below; all changes are confined to this invocation's subshell.
  set +f

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --key|-k)
        [ "$#" -ge 2 ] || break
        em_concurrent_key="$2"
        em_concurrent_keyed=true
        shift 2
        ;;
      *) break ;;
    esac
  done
  em_concurrent_limit="${1-}"
  case "$em_concurrent_limit" in
    ''|0*|*[!0-9]*) em_concurrent_limit= ;;
  esac
  if [ -z "$em_concurrent_limit" ] || [ "${#em_concurrent_limit}" -gt 9 ] || [ "$#" -lt 2 ]; then
    printf '%s\n' 'Usage: em_run_concurrent [--key KEY] N [--] COMMAND [ARG ...]' >&2
    return 2
  fi
  shift
  [ "$1" != -- ] || shift
  if [ "$#" -eq 0 ]; then
    printf '%s\n' 'em_run_concurrent: no command given' >&2
    return 2
  fi

  # A stable per-user path coordinates shells even when their TMPDIR differs.
  em_concurrent_root="${ENVMANAGER_CONCURRENCY_DIR:-${XDG_STATE_HOME:-${HOME:+$HOME/.local/state}}/envmanager/concurrent}"
  case "$em_concurrent_root" in
    /*) ;;
    *) printf '%s\n' 'em_run_concurrent: set an absolute ENVMANAGER_CONCURRENCY_DIR or HOME/XDG_STATE_HOME' >&2; return 2 ;;
  esac
  if [ -z "${ENVMANAGER_CONCURRENCY_DIR:-${XDG_STATE_HOME:-${HOME:-}}}" ]; then
    printf '%s\n' 'em_run_concurrent: set ENVMANAGER_CONCURRENCY_DIR or HOME/XDG_STATE_HOME' >&2
    return 2
  fi

  # NUL boundaries distinguish e.g. ("a b", "c") from ("a", "b c"),
  # including empty arguments and trailing newlines. Use the same hash algorithm
  # across shells, independently of optional tools on their PATH.
  em_concurrent_hash="$(
    if [ "$em_concurrent_keyed" = true ]; then
      printf 'key\000%s\000' "$em_concurrent_key"
    else
      printf 'argv\000'; printf '%s\000' "$@"
    fi | _em_concurrent_hash
  )" || return
  em_concurrent_hash="${em_concurrent_hash%% *}"
  em_concurrent_root="$em_concurrent_root/$em_concurrent_hash"
  (umask 077; command mkdir -p "$em_concurrent_root") || return

  trap '_em_concurrent_cleanup' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # $$ still names the original shell in subshells, and Bash 3.2 has no
  # BASHPID. Run this probe directly: command substitution would add another
  # parent process on shells that do not optimize away the intermediate shell.
  em_concurrent_probe="$(command mktemp "$em_concurrent_root/pid.XXXXXXXXXX")" || return
  command sh -c 'printf "%s\n" "$PPID"' > "$em_concurrent_probe" || return
  IFS= read -r em_concurrent_owner < "$em_concurrent_probe" || return
  command rm -f "$em_concurrent_probe" || return
  em_concurrent_probe=
  em_concurrent_request="$(command mktemp -d "$em_concurrent_root/$em_concurrent_owner.XXXXXXXXXX")" || return

  # Lamport's bakery admission, generalized to N places: publish "choosing"
  # by creating our directory, then atomically publish a ticket. A request can
  # run when fewer than N earlier tickets remain. No shared read/modify/write
  # counter or stale reusable mutex is needed. Unique names break ticket ties.
  for em_concurrent_other in "$em_concurrent_root"/*; do
    em_concurrent_other="${em_concurrent_other%/}"
    [ -f "$em_concurrent_other/ticket" ] || continue
    em_concurrent_number=
    { IFS= read -r em_concurrent_number < "$em_concurrent_other/ticket"; } 2>/dev/null || continue
    if [ "$em_concurrent_number" -gt "$em_concurrent_max" ]; then
      em_concurrent_max="$em_concurrent_number"
    fi
  done
  em_concurrent_ticket=$((em_concurrent_max + 1))
  printf '%s\n' "$em_concurrent_ticket" > "$em_concurrent_request/ticket.new" || return
  command mv "$em_concurrent_request/ticket.new" "$em_concurrent_request/ticket" || return

  while :; do
    em_concurrent_before=0
    em_concurrent_choosing=false
    for em_concurrent_other in "$em_concurrent_root"/*; do
      em_concurrent_other="${em_concurrent_other%/}"
      [ "$em_concurrent_other" != "$em_concurrent_request" ] || continue
      [ -d "$em_concurrent_other" ] || continue
      if ! _em_concurrent_alive "$em_concurrent_other"; then
        command rm -rf "$em_concurrent_other" || return
        continue
      fi
      em_concurrent_number=
      if ! { IFS= read -r em_concurrent_number < "$em_concurrent_other/ticket"; } 2>/dev/null; then
        [ ! -d "$em_concurrent_other" ] || em_concurrent_choosing=true
        continue
      fi
      if [ "$em_concurrent_number" -lt "$em_concurrent_ticket" ] || {
        [ "$em_concurrent_number" -eq "$em_concurrent_ticket" ] &&
        _em_concurrent_precedes "$em_concurrent_other" "$em_concurrent_request"
      }; then
        em_concurrent_before=$((em_concurrent_before + 1))
      fi
    done
    if [ "$em_concurrent_choosing" = false ] && em_concurrency_available "$em_concurrent_before" "$em_concurrent_limit"; then
      break
    fi
    command sleep 0.05 || return
  done

  # The worker retains its ticket until the command returns, even if the
  # invoking shell is killed. Do not start the command until its PID has been
  # published: a dead caller can then be reaped without losing a live worker.
  (
    em_concurrent_worker=
    trap '_em_concurrent_cleanup' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    while [ ! -f "$em_concurrent_request/worker" ]; do
      kill -0 "$em_concurrent_owner" 2>/dev/null || exit 125
      command sleep 0.05 || exit
    done
    case "$em_concurrent_shell_flags" in *f*) set -f ;; esac
    if [ "$em_concurrent_globignore_set" = x ]; then
      GLOBIGNORE="$em_concurrent_globignore"
    else
      unset GLOBIGNORE
    fi
    "$@"
  ) <&0 &
  em_concurrent_worker=$!
  printf '%s\n' "$em_concurrent_worker" > "$em_concurrent_request/worker.new" || return
  command mv "$em_concurrent_request/worker.new" "$em_concurrent_request/worker" || return
  if wait "$em_concurrent_worker"; then
    em_concurrent_result=0
  else
    em_concurrent_result=$?
  fi
  em_concurrent_worker=
  return "$em_concurrent_result"
)

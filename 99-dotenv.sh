#!/bin/bash

# Load the `.env` files found between the current directory and the filesystem
# root, walking upwards one parent at a time.
#
# Rules:
#
# 1. The nearest file wins: directories are visited from `$PWD` upwards, so a
#    `.env` in the current folder takes precedence over one in a parent folder.
# 2. Variables that are already defined — by the shell, by the inherited
#    environment, or by a nearer `.env` — are never replaced.
# 3. A collision is announced on stderr as a yellow warning. Only the variable
#    name and the file are printed, never the value, so secrets are not echoed
#    into the terminal or into shell logs.
#
# A collision means "a value this script did not put there is in the way, so the
# file was ignored". The cases that are *not* collisions are kept quiet on
# purpose, since a warning nobody can act on is a warning nobody reads:
#
# - The file agrees with the current value. Nothing is being lost.
# - A nearer `.env` already won. That is the documented precedence, not a clash.
# - The value came from an earlier walk of this same script and nobody has
#   touched it since. It is ours to refresh.
#
# The last case is what makes the loader safe to re-run. `em_dotenv_load` is left
# defined on purpose: hook it into `chpwd` (Zsh) or `PROMPT_COMMAND` (Bash) to
# re-read the files on every `cd`. Variables that fall out of the tree along the
# way are unset again, so values do not leak from one project into the next.

# Name of the files to look for.
ENVMANAGER_DOTENV_FILENAME="${ENVMANAGER_DOTENV_FILENAME:-.env}"

# Topmost directory to visit. The walk also stops at `/`, so a root that is not
# an ancestor of the current directory simply means "walk all the way up".
ENVMANAGER_DOTENV_ROOT="${ENVMANAGER_DOTENV_ROOT:-/}"

# Set to `false` to silence the collision warnings.
ENVMANAGER_DOTENV_WARN="${ENVMANAGER_DOTENV_WARN:-true}"

# Space-separated names that never warn, for variables the shell is expected to
# own (e.g. `ENVMANAGER_DOTENV_IGNORE="PATH TERM"`).
ENVMANAGER_DOTENV_IGNORE="${ENVMANAGER_DOTENV_IGNORE:-}"

# Bumped once per walk, so a variable can tell "set by a nearer file during this
# walk" from "left over from an earlier walk".
ENVMANAGER_DOTENV_RUN=0

# Newline-separated names this script currently owns.
ENVMANAGER_DOTENV_MANAGED=""

# Per-variable bookkeeping is held in `_EM_DOTENV_<FIELD>_<KEY>` variables rather
# than in an associative array, which Bash and Zsh spell differently. Variable
# names are validated before they reach here, so the expansion is safe.
em_dotenv_state_read() {
  local destination="$1"
  local field="$2"
  local key="$3"

  eval "$destination=\"\${_EM_DOTENV_${field}_${key}-}\""
}

em_dotenv_state_write() {
  local field="$1"
  local key="$2"

  eval "_EM_DOTENV_${field}_${key}=\$3"
}

em_dotenv_state_clear() {
  local key="$1"

  eval "unset _EM_DOTENV_FILE_$key _EM_DOTENV_VALUE_$key _EM_DOTENV_RUN_$key _EM_DOTENV_OWNED_$key"
}

# Print a yellow warning on stderr. Colors are emitted only when stderr is a
# terminal, so redirected output stays clean.
em_dotenv_warn() {
  if [ "$ENVMANAGER_DOTENV_WARN" != "true" ]; then
    return 0
  fi

  local format="$1"
  shift

  local yellow=""
  local reset=""
  if [ -t 2 ]; then
    yellow=$'\033[33m'
    reset=$'\033[0m'
  fi

  local message
  # shellcheck disable=SC2059 # the format string is ours, never the file's.
  message="$(printf "$format" "$@")"

  printf '%s%s%s\n' "$yellow" "$message" "$reset" >&2
}

# Warn about a subject — a variable name, or an offending line — at most once per
# file for the lifetime of the shell. Without this guard a loader hooked into
# `cd` would repeat the same warning on every prompt, which is the fastest way to
# teach someone to ignore it.
em_dotenv_warn_once() {
  local file="$1"
  local subject="$2"
  shift 2

  case " $ENVMANAGER_DOTENV_IGNORE " in
    *" $subject "*) return 0 ;;
  esac

  local token="${file//[^A-Za-z0-9_]/_}_${subject//[^A-Za-z0-9_]/_}"
  local warned
  em_dotenv_state_read warned WARNED "$token"

  if [ -n "$warned" ]; then
    return 0
  fi

  em_dotenv_state_write WARNED "$token" 1

  em_dotenv_warn "$@"
}

# Strip the leading and trailing whitespace of a string.
em_dotenv_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Resolve the escape sequences a double-quoted value is allowed to carry. A
# single left-to-right pass is used so that an escaped backslash cannot be
# mistaken for the start of another sequence (`"\\n"` is a backslash and an `n`,
# not a newline).
em_dotenv_unescape() {
  local rest="$1"
  local output=""

  while [ -n "$rest" ]; do
    case "$rest" in
      '\n'*) output="$output"$'\n'; rest="${rest#??}" ;;
      '\t'*) output="$output"$'\t'; rest="${rest#??}" ;;
      '\r'*) output="$output"$'\r'; rest="${rest#??}" ;;
      '\"'*) output="$output"'"';   rest="${rest#??}" ;;
      '\\'*) output="$output"'\';   rest="${rest#??}" ;;
      *) output="$output${rest%"${rest#?}"}"; rest="${rest#?}" ;;
    esac
  done

  printf '%s' "$output"
}

# Turn the right-hand side of an assignment into the value to export.
em_dotenv_parse_value() {
  local value
  value="$(em_dotenv_trim "$1")"

  case "$value" in
    '"'*'"')
      value="${value#\"}"
      value="${value%\"}"
      value="$(em_dotenv_unescape "$value")"
      ;;
    "'"*"'")
      # Single-quoted values are literal.
      value="${value#\'}"
      value="${value%\'}"
      ;;
    *)
      # An unquoted value ends at the first inline comment.
      case "$value" in
        *[[:space:]]'#'*) value="$(em_dotenv_trim "${value%%[[:space:]]'#'*}")" ;;
      esac
      ;;
  esac

  printf '%s' "$value"
}

# Export a variable and record that this script owns it.
em_dotenv_apply() {
  local key="$1"
  local value="$2"
  local file="$3"

  export "$key"="$value"

  em_dotenv_state_write FILE "$key" "$file"
  em_dotenv_state_write VALUE "$key" "$value"
  em_dotenv_state_write RUN "$key" "$ENVMANAGER_DOTENV_RUN"

  local owned
  em_dotenv_state_read owned OWNED "$key"

  if [ -z "$owned" ]; then
    em_dotenv_state_write OWNED "$key" 1
    ENVMANAGER_DOTENV_MANAGED="$ENVMANAGER_DOTENV_MANAGED$key"$'\n'
  fi

  em_print_debug 'dotenv: %s: exported %s\n' "$file" "$key"
}

# Export every assignment of a single file that does not collide with a value
# this script did not set.
em_dotenv_load_file() {
  local file="$1"
  local line
  local key
  local value
  local current
  local owned
  local previous_value
  local previous_run
  local previous_file

  # The `-n "$line"` guard makes the last line count even without a trailing
  # newline.
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(em_dotenv_trim "$line")"

    case "$line" in
      '' | '#'*) continue ;;
    esac

    # Both `FOO=bar` and `export FOO=bar` are accepted.
    case "$line" in
      'export '* | 'export'$'\t'*) line="$(em_dotenv_trim "${line#export}")" ;;
    esac

    case "$line" in
      *=*) ;;
      *)
        em_dotenv_warn_once "$file" "$line" \
          'dotenv: %s: ignoring line without an assignment: %s' "$file" "$line"
        continue
        ;;
    esac

    key="$(em_dotenv_trim "${line%%=*}")"

    case "$key" in
      '' | [0-9]* | *[!A-Za-z0-9_]*)
        em_dotenv_warn_once "$file" "$key" \
          'dotenv: %s: ignoring invalid variable name: %s' "$file" "$key"
        continue
        ;;
    esac

    value="$(em_dotenv_parse_value "${line#*=}")"
    current="$(em_get_var_value "$key")"

    em_dotenv_state_read owned OWNED "$key"
    em_dotenv_state_read previous_value VALUE "$key"
    em_dotenv_state_read previous_run RUN "$key"
    em_dotenv_state_read previous_file FILE "$key"

    # Nothing is in the way: the file owns the variable.
    if [ -z "$current" ]; then
      em_dotenv_apply "$key" "$value" "$file"
      continue
    fi

    # The file asks for the value that is already there. Not a collision — but
    # refresh the bookkeeping if the value is ours, so that it survives the
    # stale-variable sweep at the end of the walk.
    if [ "$current" = "$value" ]; then
      if [ -n "$owned" ]; then
        em_dotenv_apply "$key" "$value" "$file"
      else
        em_print_debug 'dotenv: %s: %s already holds this value\n' "$file" "$key"
      fi
      continue
    fi

    # The value in the way is one we set and nobody has touched since.
    if [ -n "$owned" ] && [ "$current" = "$previous_value" ]; then
      if [ "$previous_run" != "$ENVMANAGER_DOTENV_RUN" ]; then
        # Left over from an earlier walk — this file is now the owner.
        em_dotenv_apply "$key" "$value" "$file"
      elif [ "$previous_file" = "$file" ]; then
        em_dotenv_warn_once "$file" "$key" \
          'dotenv: %s: ignoring the second assignment to %s' "$file" "$key"
      else
        # A nearer file won during this same walk: documented precedence.
        em_print_debug 'dotenv: %s: %s is shadowed by %s\n' "$file" "$key" "$previous_file"
      fi
      continue
    fi

    # A value this script did not set is in the way. The file loses, and that is
    # worth saying out loud.
    em_dotenv_warn_once "$file" "$key" \
      'dotenv: %s: %s is already defined, keeping the current value' "$file" "$key"
  done < "$file"
}

# Unset the variables that were exported by an earlier walk and no longer appear
# in any `.env` of the current tree, so that leaving a project does not leak its
# values into the next one. A variable that someone else has changed in the
# meantime is left alone.
em_dotenv_forget_stale() {
  if [ -z "$ENVMANAGER_DOTENV_MANAGED" ]; then
    return 0
  fi

  local managed=""
  local key
  local run
  local value

  while IFS= read -r key; do
    if [ -z "$key" ]; then
      continue
    fi

    em_dotenv_state_read run RUN "$key"

    if [ "$run" = "$ENVMANAGER_DOTENV_RUN" ]; then
      managed="$managed$key"$'\n'
      continue
    fi

    em_dotenv_state_read value VALUE "$key"

    if [ "$(em_get_var_value "$key")" = "$value" ]; then
      unset "$key"
      em_print_debug 'dotenv: unset %s, no longer part of the tree\n' "$key"
    fi

    em_dotenv_state_clear "$key"
  done <<< "$ENVMANAGER_DOTENV_MANAGED"

  ENVMANAGER_DOTENV_MANAGED="$managed"
}

# Load the `.env` files of a directory and of each of its parents, nearest
# first.
em_dotenv_load() {
  local directory="${1:-$PWD}"

  if [ ! -d "$directory" ]; then
    return 0
  fi

  ENVMANAGER_DOTENV_RUN=$(( ENVMANAGER_DOTENV_RUN + 1 ))

  local directories=()
  local parent

  while true; do
    directories+=("$directory")

    if [ "$directory" = "$ENVMANAGER_DOTENV_ROOT" ] || [ "$directory" = "/" ]; then
      break
    fi

    parent="${directory%/*}"
    directory="${parent:-/}"
  done

  local file
  for directory in "${directories[@]}"; do
    file="$directory/$ENVMANAGER_DOTENV_FILENAME"

    if [ -f "$file" ] && [ -r "$file" ]; then
      em_dotenv_load_file "$file"
    fi
  done

  em_dotenv_forget_stale
}

em_dotenv_load

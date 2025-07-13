#!/bin/bash

# If `TMPDIR` is already set, do nothing
# If you want to set your `TMPDIR` yourself, create `00-tmpdior.local.sh`. It will be ignored by Git, and if the environment variable is set, it will not be overwritten by this script.

# Compute a temporary directory path based on the XDG Base Directory Specification
# if TMPDIR is not set. It will iterate over the directories and use the first one
# that exists. The order of preference is:
#
# 1. $XDG_RUNTIME_DIR
# 2. $XDG_CACHE_HOME
# 3. $XDG_CONFIG_HOME
# 4. $XDG_DATA_HOME
# 5. $HOME
# 6. $PWD
compute_tmpdir() {
  # Unset this function, we only need to run it once
  unset -f compute_tmpdir

  # List XDG directories and look for the most suitable one to be used as a temporary directory
  directories=(
    "$XDG_RUNTIME_DIR"
    "$XDG_CACHE_HOME"
    "$XDG_CONFIG_HOME"
    "$XDG_DATA_HOME"
    "$HOME"
    "$PWD"
  )

  for directory in "${directories[@]}"; do
    if [ ! -d "$directory" ]; then
      break
    fi
    TMPDIR="$directory/tmp"
  done

  # If `TMPDIR` is still not set, check for `mktemp` existence
  if [ -z "$TMPDIR" ]; then
    if command -v mktemp &>/dev/null; then
      TMPDIR="$(mktemp -d)"
    fi
  fi

  export TMPDIR
}

if [ -z "$TMPDIR" ]; then
  compute_tmpdir
fi

if [ -n "$TMPDIR" ] && [ ! -d "$TMPDIR" ]; then
  printf '%s is set to "%s", but it does not exist. Creating it...\n' "TMPDIR" "$TMPDIR"
  mkdir --parents --verbose "$TMPDIR"
fi

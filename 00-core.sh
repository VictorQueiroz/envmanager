#!/bin/bash

# Compatible startup entry point; lib/*.sh only define functions.
ENVMANAGER_DIR="${ENVMANAGER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/envmanager}"

. "$ENVMANAGER_DIR/lib/platform.sh" || return
. "$ENVMANAGER_DIR/lib/environment.sh" || return
. "$ENVMANAGER_DIR/lib/scripts.sh" || return
. "$ENVMANAGER_DIR/lib/run-every.sh" || return
. "$ENVMANAGER_DIR/lib/run-concurrent.sh" || return
. "$ENVMANAGER_DIR/lib/shell.sh" || return

# Zsh owns command tracing; other shells keep their existing startup behavior.
if [ -n "${ZSH_VERSION:-}" ]; then
  if ! typeset -f em_benchmark_start >/dev/null; then
    . "$ENVMANAGER_DIR/lib/benchmark-zsh.sh" || return
  fi
  em_benchmark_auto
fi

em_init

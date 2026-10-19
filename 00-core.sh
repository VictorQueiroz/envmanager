#!/bin/bash

# Compatible startup entry point; lib/*.sh only define functions.
ENVMANAGER_DIR="${ENVMANAGER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/envmanager}"

. "$ENVMANAGER_DIR/lib/platform.sh" || return
. "$ENVMANAGER_DIR/lib/environment.sh" || return
. "$ENVMANAGER_DIR/lib/scripts.sh" || return
. "$ENVMANAGER_DIR/lib/run-every.sh" || return
. "$ENVMANAGER_DIR/lib/shell.sh" || return

em_init

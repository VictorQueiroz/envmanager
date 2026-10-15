#!/bin/bash

# Compatible startup entry point; lib/*.sh only define functions.
ENVMANAGER_DIR="${ENVMANAGER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/envmanager}"

source "$ENVMANAGER_DIR/lib/environment.sh" || return
source "$ENVMANAGER_DIR/lib/scripts.sh" || return
source "$ENVMANAGER_DIR/lib/run-every.sh" || return
source "$ENVMANAGER_DIR/lib/shell.sh" || return

em_init

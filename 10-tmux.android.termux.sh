#!/bin/sh

# Configure sockets without cloning/updating the desktop tmux configuration.
em_export_alternatives TMUX_TMPDIR "$TMPDIR/tmux"
em_mkdir "$TMUX_TMPDIR"

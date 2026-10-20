#!/bin/bash

# Reuse Codex's conventional home when no XDG home has been established.
em_export_path CODEX_HOME "$XDG_DATA_HOME/codex" "${HOME:+$HOME/.codex}"

# Preserve an established XDG state split. Native/custom homes keep their own
# SQLite databases instead of picking up state from a different Codex home.
if [ "$CODEX_HOME" = "$XDG_DATA_HOME/codex" ]; then
  em_export_path CODEX_SQLITE_HOME "$XDG_STATE_HOME/codex" "$CODEX_HOME"
else
  em_export_path CODEX_SQLITE_HOME "$CODEX_HOME"
fi

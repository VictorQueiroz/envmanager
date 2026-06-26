#!/bin/bash

# Codex stores config, sessions, and data under CODEX_HOME (default ~/.codex).
em_export_alternatives "CODEX_HOME" "$XDG_DATA_HOME/codex"
# SQLite state DB; defaults to $CODEX_HOME — split it into the state dir.
em_export_alternatives "CODEX_SQLITE_HOME" "$XDG_STATE_HOME/codex"

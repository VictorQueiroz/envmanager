#!/bin/bash

# Keep the fallback under the calling user's home when TMPDIR is unavailable.
em_export_path CLAUDE_CODE_TMPDIR "${TMPDIR:-$HOME/.tmp}/claude-code"

# Opt out of non-essential telemetry/usage traffic.
em_export_alternatives "DISABLE_TELEMETRY" "1"


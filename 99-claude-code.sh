#!/bin/bash

# Keep the fallback under the calling user's home when TMPDIR is unavailable.
em_export_path CLAUDE_CODE_TMPDIR "${TMPDIR:-$HOME/.tmp}/claude-code"

# Shared telemetry opt-outs are configured by 01-disable-telemetry.sh.


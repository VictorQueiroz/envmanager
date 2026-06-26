#!/bin/bash

# `${TMPDIR:+...}` drops the alternative when TMPDIR is empty, so we fall through
# to the /storage default instead of selecting a bare "/claude-code".
em_export_alternatives "CLAUDE_CODE_TMPDIR" "${TMPDIR:+$TMPDIR/claude-code}" "/storage/Temp/claude-code"

# Opt out of non-essential telemetry/usage traffic.
em_export_alternatives "DISABLE_TELEMETRY" "1"


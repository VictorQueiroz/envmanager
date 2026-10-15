#!/bin/bash

# Set GPG_TTY to the current terminal

# Check if `tty` command is available
if command -v tty &>/dev/null; then
  GPG_TTY="$(tty)"
else
  # Fallback to `/dev/tty`
  GPG_TTY="/dev/tty"
fi

if [ -n "$GPG_TTY" ]; then
  export GPG_TTY
fi

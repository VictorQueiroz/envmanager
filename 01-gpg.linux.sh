#!/bin/bash

# Set GPG_TTY to the current terminal

set_gpg_tty() {
  unset -f set_gpg_tty

  # If the GPG_TTY environment variable is already set, use it
  if [ -n "$GPG_TTY" ]; then
    return 0
  fi

  # Check if `tty` command is available
  if command -v tty &>/dev/null; then
    GPG_TTY="$(tty)"
    # Verify that the terminal is valid
    if [ ! -e "$GPG_TTY" ]; then
      GPG_TTY="/dev/tty"
    fi
  else
    # Fallback to `/dev/tty`
    GPG_TTY="/dev/tty"
  fi

  if [ -n "$GPG_TTY" ]; then
    export GPG_TTY
  fi
}

# Call the function to set GPG_TTY
set_gpg_tty
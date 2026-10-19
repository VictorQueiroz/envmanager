#!/bin/sh

# Selecting a handler does not launch an intent or request Android permissions.
if [ -z "${BROWSER:-}" ] && command -v termux-open-url >/dev/null 2>&1; then
  BROWSER="$(command -v termux-open-url)"
  export BROWSER
fi

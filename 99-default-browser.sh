#!/bin/bash

# List of common browser executable names, ordered by priority (most stable first)
executables=(
  google-chrome-stable
  google-chrome
  google-chrome-beta
  google-chrome-unstable
  chrome
  chromium
  chromium-browser
  firefox
  opera
  brave-browser
  vivaldi
)
BROWSER=

# Iterate over the list and assign the first found browser
for cmd in "${executables[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    BROWSER="$(command -v "$cmd")"
    break
  fi
done

# Export the `BROWSER` environment variable
export BROWSER

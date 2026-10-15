#!/bin/bash

HOMEBREW_PREFIX=/opt/homebrew
export HOMEBREW_PREFIX

# Prepend Homebrew's `bin` and `sbin` directories to `PATH`
PATH="$HOMEBREW_PREFIX/bin:$PATH"
PATH="$HOMEBREW_PREFIX/sbin:$PATH"
export PATH

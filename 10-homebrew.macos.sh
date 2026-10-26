#!/bin/bash

HOMEBREW_PREFIX=/opt/homebrew
export HOMEBREW_PREFIX

# Prepend Homebrew's `bin` and `sbin` directories to `PATH`
em_add_path PATH "$HOMEBREW_PREFIX/bin" prepend-move
em_add_path PATH "$HOMEBREW_PREFIX/sbin" prepend-move

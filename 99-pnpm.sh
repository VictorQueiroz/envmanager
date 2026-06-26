#!/bin/bash

# PNPM home directory
PNPM_HOME="$XDG_DATA_HOME/pnpm"
export PNPM_HOME

PATH="$PATH:$PNPM_HOME/bin"
export PATH

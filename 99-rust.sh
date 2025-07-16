#!/bin/bash

CARGO_HOME="$XDG_DATA_HOME"/cargo
export CARGO_HOME

# Add cargo binary folders
PATH="${PATH}:${CARGO_HOME}/bin"
export PATH

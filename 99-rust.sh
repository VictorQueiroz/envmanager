#!/bin/bash

em_export_path CARGO_HOME "$XDG_DATA_HOME/cargo" "${HOME:+$HOME/.cargo}"

# Add cargo binary folders
em_add_path PATH "$CARGO_HOME/bin"

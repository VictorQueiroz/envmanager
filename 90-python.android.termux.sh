#!/bin/sh

# Use Python/uv installed for Termux's Bionic environment. Never bootstrap pyenv
# or download a desktop Python build during shell startup.
em_export_alternatives UV_PYTHON_DOWNLOADS never
em_export_path UV_CACHE_DIR "$XDG_CACHE_HOME/uv"

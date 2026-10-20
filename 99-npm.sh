#!/bin/bash

em_export_path NPM_CONFIG_USERCONFIG "$XDG_CONFIG_HOME/npm/npmrc" "${HOME:+$HOME/.npmrc}"

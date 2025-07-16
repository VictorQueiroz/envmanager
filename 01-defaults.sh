#!/bin/bash

em_export_alternatives "HOME" "/tmp/user-0001"
em_export_alternatives "XDG_CACHE_HOME" "${HOME}/.cache"
em_export_alternatives "XDG_DATA_HOME" "${HOME}/.local/share"
em_export_alternatives "XDG_CONFIG_HOME" "${HOME}/.config"
em_export_alternatives "XDG_STATE_HOME" "${HOME}/.local/state"

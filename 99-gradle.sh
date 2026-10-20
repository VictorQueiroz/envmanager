#!/bin/bash

em_export_path GRADLE_USER_HOME "$XDG_DATA_HOME/gradle" "${HOME:+$HOME/.gradle}"

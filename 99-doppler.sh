#!/bin/bash

em_export_path DOPPLER_INSTALL_DIR "$XDG_DATA_HOME/doppler"
DOPPLER_BIN="$DOPPLER_INSTALL_DIR/doppler"

em_add_path PATH "$DOPPLER_INSTALL_DIR" prepend-move

if [ ! -f "$DOPPLER_BIN" ]; then
  em_mkdir "$DOPPLER_INSTALL_DIR"
  (
    curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh || wget -t 3 -qO- https://cli.doppler.com/install.sh
  ) | sh -s -- --install-path "$DOPPLER_INSTALL_DIR" --version latest
fi

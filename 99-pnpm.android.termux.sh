#!/bin/sh

# Reuse an existing pnpm installation; package installation is user-managed.
em_export_path PNPM_HOME "$XDG_DATA_HOME/pnpm"
for em_pnpm_directory in "$PNPM_HOME" "$PNPM_HOME/bin"; do
  if [ -x "$em_pnpm_directory/pnpm" ]; then
    em_add_path PATH "$em_pnpm_directory" prepend
  fi
done
export PATH
unset em_pnpm_directory

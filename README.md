# envmanager

### Installation

Add this to your `~/.envmanagerrc`:

```
#!/bin/bash

envmanager_load() {
  local envmanager_repo_url
  envmanager_repo_url="https://github.com/VictorQueiroz/envmanager.git"

  ENVMANAGER_DIR="$XDG_CONFIG_HOME"/envmanager
  
  if [[ -d "$ENVMANAGER_DIR" ]]; then
    git -C "$ENVMANAGER_DIR" clone "$envmanager_repo_url"
  fi

  local find_args
  find_args=(
    "${ENVMANAGER_DIR}"
    -maxdepth 1
    -name '*.sh'
    -type f
    -print
    -executable
  )
  while IFS= read -r file; do
    source "$file"
  done < <(find "${find_args[@]}" | sort)

  # Update the repository every 1 day
  em_run_every 1d git -C "$ENVMANAGER_DIR" pull
}

envmanager_load
unset -f envmanager_load
```

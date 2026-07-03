# envmanager

## Installation

### 1. Create `"$HOME"/.envmanagerrc`

```sh
#!/bin/bash

envmanager_load() {
  local envmanager_repo_url
  envmanager_repo_url="https://github.com/VictorQueiroz/envmanager.git"

  local home_dir
  home_dir="$HOME"

  if [[ ! -d "$home_dir" ]]; then
    return 1
  fi

  local envmanager_root_directory
  envmanager_root_directory="${XDG_CONFIG_HOME:-$home_dir/.config}"
  ENVMANAGER_DIR="$envmanager_root_directory"/envmanager
  
  if [[ ! -d "$ENVMANAGER_DIR" ]]; then
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

### 2. Source it from your `~/.bashrc` or `~/.zshrc`

```sh
source "$HOME"/.envmanagerrc
```

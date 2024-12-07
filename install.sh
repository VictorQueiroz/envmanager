!#/bin/bash

# If the HOME environment variable does not exist, print an error
clone_envmanager_configuration() {
  unset -f clone_envmanager_configuration

  git_args=(
    clone https://github.com/VictorQueiroz/envmanager.git
    "$HOME"/.config/envmanager
  )

  git "${git_args[@]}"
}

clone_envmanager_configuration

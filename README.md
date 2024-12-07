# EnvManager configuration 

## Features

- Downloads Node.js version manager automatically to `$HOME/.config/nvim`
- Sets the `EDITOR` environment variable based on the first available editor
- Sets the `TERM` environment variable based on the current terminal

## Missing

- Sets the `VISUAL` environment variable based on the first available editor

## Environment variables

### EDITOR
  - `nvim`
  - `vim`
  - `vi`
  - `nano`

### TERM

1. If `$TMUX` environment variable is not empty, `xterm-256color` will be set.
2. Otherwise, `rxvt-unicode-256color` will be set.

## Installation

```bash
curl https://raw.githubusercontent.com/VictorQueiroz/envmanager/refs/heads/master/install.sh | bash
```

or

```bash
git clone https://github.com/VictorQueiroz/envmanager.git ~/.config/envmanager
```

## Local shell script files

Files ending with `.local.sh` will not be tracked in version control.

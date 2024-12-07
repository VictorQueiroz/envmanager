#!/bin/bash

export TERM
if [ -z "$TMUX" ]; then
  # If we're outside of Tmux, use rxvt-unicode-256color
  TERM="rxvt-unicode-256color"
else
  TERM="tmux-256color"
fi


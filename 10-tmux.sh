#!/bin/bash

# TMUX(1)                          General Commands Manual                         TMUX(1)
#
# GLOBAL AND SESSION ENVIRONMENT
#        When the  server  is  started,  tmux  copies  the  environment  into  the  global
#        environment;  in addition, each session has a session environment.  When a window
#        is created, the session and global environments are merged.  If a variable exists
#        in both, the value from the session environment is used.  The result is the  ini‐
#        tial environment passed to the new process.
#
#        The  update-environment session option may be used to update the session environ‐
#        ment from the client when a new session is created or an  old  reattached.   tmux
#        also  initialises  the TMUX variable with some internal information to allow com‐
#        mands to be executed from inside, and the TERM variable with the correct terminal
#        setting of ‘screen’.
#
#        Variables in both session and global environments may be marked as hidden.   Hid‐
#        den  variables  are  not passed into the environment of new processes and instead
#        can only be used by tmux itself (for example in formats, see the  “FORMATS”  sec‐
#        tion).
#
#        Commands to alter and view the environment are:
#
#        set-environment [-Fhgru] [-t target-session] name [value]
#                      (alias: setenv)
#                Set  or unset an environment variable.  If -g is used, the change is made
#                in the global environment; otherwise, it is applied to the session  envi‐
#                ronment  for target-session.  If -F is present, then value is expanded as
#                a format.  The -u flag unsets a variable.  -r indicates the  variable  is
#                to  be  removed  from  the environment before starting a new process.  -h
#                marks the variable as hidden.
#
#        show-environment [-hgs] [-t target-session] [variable]
#                      (alias: showenv)
#                Display the environment for target-session or the global environment with
#                -g.  If variable is omitted, all variables are shown.  Variables  removed
#                from the environment are prefixed with ‘-’.  If -s is used, the output is
#                formatted  as  a set of Bourne shell commands.  -h shows hidden variables
#                (omitted by default).
#
# ENVIRONMENT
#        When tmux is started, it inspects the following environment variables:
#
#        EDITOR    If  the command specified in this variable contains the string ‘vi’ and
#                  VISUAL  is  unset,  use  vi-style  key  bindings.   Overridden  by  the
#                  mode-keys and status-keys options.
#
#        HOME      The  user's  login directory.  If unset, the passwd(5) database is con‐
#                  sulted.
#
#        LC_CTYPE  The character encoding locale(1).  It is used  for  two  separate  pur‐
#                  poses.   For  output to the terminal, UTF-8 is used if the -u option is
#                  given or if LC_CTYPE contains "UTF-8" or "UTF8".  Otherwise, only ASCII
#                  characters are written and non-ASCII characters are replaced  with  un‐
#                  derscores  (‘_’).  For input, tmux always runs with a UTF-8 locale.  If
#                  en_US.UTF-8 is provided  by  the  operating  system,  it  is  used  and
#                  LC_CTYPE is ignored for input.  Otherwise, LC_CTYPE tells tmux what the
#                  UTF-8  locale is called on the current system.  If the locale specified
#                  by LC_CTYPE is not available or is not a UTF-8 locale, tmux exits  with
#                  an error message.
#
#        LC_TIME   The  date  and  time format locale(1).  It is used for locale-dependent
#                  strftime(3) format specifiers.
#
#        PWD       The current working directory to be  set  in  the  global  environment.
#                  This  may be useful if it contains symbolic links.  If the value of the
#                  variable does not match the current working directory, the variable  is
#                  ignored and the result of getcwd(3) is used instead.
#
#        SHELL     The  absolute  path  to  the  default  shell  for new windows.  See the
#                  default-shell option for details.
#
#        TMUX_TMPDIR
#                  The parent directory of the directory containing  the  server  sockets.
#                  See the -L option for details.
#
#        VISUAL    If the command specified in this variable contains the string ‘vi’, use
#                  vi-style key bindings.  Overridden by the mode-keys and status-keys op‐
#                  tions.
#
# FILES
#        ~/.tmux.conf
#        $XDG_CONFIG_HOME/tmux/tmux.conf
#        ~/.config/tmux/tmux.conf
#                           Default tmux configuration file.
#        /etc/tmux.conf     System-wide configuration file.

set_tmux_tmpdir() {
  unset -f set_tmux_tmpdir

  # If `TMPDIR` environment variable is set, set `TMUX_TMPDIR` environment variable
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    TMUX_TMPDIR="$TMPDIR/tmux/tmp"
  else
    return
  fi

  export TMUX_TMPDIR
}

if [ -z "$TMUX_TMPDIR" ]; then
  set_tmux_tmpdir
fi

# If `TMUX_TMPDIR` environment variable is set, and the directory does not exist, create it
if [ -n "$TMUX_TMPDIR" ] && [ ! -d "$TMUX_TMPDIR" ]; then
  printf '%s is set to "%s", but it does not exist. Creating it...\n' "TMUX_TMPDIR" "$TMUX_TMPDIR"
  mkdir --parents --verbose "$TMUX_TMPDIR"
fi

### © technosophist
###
### This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy
### of the MPL was not distributed with this file, You can obtain one at
### http://mozilla.org/MPL/2.0/.
###
### This Source Code Form is "Incompatible With Secondary Licenses", as defined by the Mozilla
### Public License, v. 2.0.

## Add command to existing trapped signals commands.
##
## Arguments:
## command :: command to add to trapped signals commands.
## *       :: signal names or numbers to trap, defaults to EXIT SIGHUP SIGINT SIGQUIT SIGPIPE
##            SIGTERM
addtrap() {
  # https://vegardit.com/en/blog/bash-trap/
  local cmd=$1 # command(s) to add
  shift
  declare -a sigs
  if ! (($#)); then
    sigs=(EXIT SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM)
  else
    sigs=("${@}")
  fi
  for sig in "${sigs[@]}"; do
    # validate signal name or numeric id
    local sig_name
    {
      if [[ $sig =~ ^[0-9]+$ ]]; then
        sig_name=$(kill -l "$sig")
      else
        sig_name=${sig^^}
        kill -l "$sig_name" &>/dev/null
      fi
    } || {
      die "add_trap: invalid signal '$sig'"
    }

    # Compute effective trap list for current (sub)shell
    # Based on info from https://stackoverflow.com/a/59307894/5116073
    local old
    if [[ ${BASH_VERSINFO:-0} -ge 4 ]]; then
      trap -- KILL &>/dev/null || true
      old=$(trap -p "$sig_name")
    else
      # (technosophist) shfmt keeps removing the parentheses, so I added `true`
      old="$(
        true
        (trap -p "$sig_name")
      )"
    fi

    # extract/cleanup the existing registered command(s)
    old=${old#*\'}         # remove leading "trap -- '"
    old=${old%\'*}         # remove trailing "' EXIT"
    old=${old//"'\''"/"'"} # unescape every '\'' to '

    # if command is already registered, do nothing
    if [[ ";$old;" == *";$cmd;"* ]]; then
      continue
    fi

    # build the new combined handler
    if [[ -n $old ]]; then
      combined="$old;$cmd"
    else
      combined="$cmd"
    fi

    # register the new combined handler
    trap -- "$combined" "$sig"
  done
}

## Print prompt prefixed with ">> " and read data into variable.
##
## Arguments:
## message  :: message to prefix with ">> " and print to STDOUT
## variable :: name of variable to store user input into
ask() {
  printf "\033[3m>>\033[0m %s" "$1"
  read -re "$2"
}

## Prompt user to confirm before continuing.
##
## If user enters 'yes', then return with status 0.  If user enters anything other than 'yes', then
## exit with status 0.
confirm() {
  ask "Would you like to continue? [yes/NO]: " choice
  case ${choice,,} in
    yes) return 0 ;;
    *) exit 0 ;;
  esac
}

## Print message prefixed with "== ", if TTFL_DEBUG or DEBUG are set.
##
## Arguments:
## message :: message to prefix with "== " and print
debug() {
  [[ ! -v DEBUG ]] && [[ ! -v TTFL_DEBUG ]] && return 0
  printf "\033[1m== %s\033[0m\n" "$1" | tee -a "${TTFL_LOGFILE:-/dev/null}" >&2
}

## Print message prefixed with "!! " to STDERR and exit with (optional) error status.
##
## Arguments:
## message :: message to prefix with "!! " and print to STDERR
## status? :: status to exit with, defaults to 1
die() {
  error "$1"
  exit "${2:-1}"
}

## Print message prefixed with "!! " to STDERR
##
## Arguments:
## message :: message to prefix with "!! " and print to STDERR
error() {
  printf "\033[1;31m!! %s\033[0m\n" "$1" | tee -a "${TTFL_LOGFILE:-/dev/null}" >&2
}

## Print message prefixed with "== "
##
## Arguments:
## message :: message to prefix with "== " and print
log() {
  printf "\033[1m== %s\033[0m\n" "$1" | tee -a "${TTFL_LOGFILE:-/dev/null}" >&2
}

## Print message prefixed with "** "
##
## Arguments:
## message :: message to prefix with "** " and print
warn() {
  printf "\033[1;33m** %s\033[0m\n" "$1" | tee -a "${TTFL_LOGFILE:-/dev/null}" >&2
}

## Print message prefixed with ">> " and read data into variable without echoing.
##
## Arguments:
## message  :: message to prefix with ">> " and print
## variable :: name of variable to store user input into
whisper() {
  read -srep "\033[3m>>\033[0m $1" "$2"
}

## Find a file in a directory or one of its parents.
##
## Arguments:
## variable  :: name of variable to store path to found file
## filename  :: filename to search for
## directory :: directory to start the search in, defaults to current directory
find-dominating-file() {
  declare -n return_value=$1
  export return_value
  filename=$2
  path="${3:-$(readlink -f .)}"
  while [[ ! -e "${path}/${filename}" ]]; do
    path=$(dirname "${path}")
    if [[ ${path} == "/" ]]; then
      unset return_value
      return 1
    fi
  done
  return_value="${path}/${filename}"
  return 0
}

## Clear lines of output before the cursor position from the terminal.
##
## Arguments:
## n :: number of lines before the cursor position to clear, defaults to 1
clear-lines() {
  # tput fails (and, under `set -e`, would otherwise abort the whole script) when there's no
  # terminal, e.g. under non-interactive/scripted invocation; clearing lines is cosmetic, so skip
  # it silently in that case rather than aborting.
  tput cr || return 0
  tput el || return 0
  for ((i = 1; i < ${1:-1}; i++)); do
    tput cuu1 || return 0
    tput el || return 0
  done
  return 0
}

## Print a message, wait for user input, then clear the message from the terminal.
##
## Arguments:
## message :: message to display to user, defaults to "Press any key to continue"
pause() {
  echo -n "${1:-Press any key to continue}"
  read -rs
  clear-lines
}

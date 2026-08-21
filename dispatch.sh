#!/bin/bash

dispatcher=${1:-}
arg=${2:-}

trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

lua_string() {
  jq -Rnr --arg value "$1" '$value | @json'
}

dispatch_lua_expression() {
  local output
  output=$(hyprctl dispatch "$1" 2>&1) || return 1
  [[ -z $output || $output == ok ]] || return 1
}

dispatch_exec() {
  dispatch_lua_expression "hl.dsp.exec_cmd($(lua_string "$1"))"
}

dispatch_sendshortcut() {
  local mods key window rest
  IFS=, read -r mods key window rest <<<"$1"
  mods=$(trim "$mods")
  key=$(trim "$key")
  window=$(trim "$window")
  [[ -n $window ]] || window=activewindow

  if [[ -n $key ]] && dispatch_lua_expression \
    "hl.dsp.send_key_state({ mods = $(lua_string "$mods"), key = $(lua_string "$key"), state = \"down\", window = $(lua_string "$window") })"; then
    sleep 0.05
    dispatch_lua_expression \
      "hl.dsp.send_key_state({ mods = $(lua_string "$mods"), key = $(lua_string "$key"), state = \"up\", window = $(lua_string "$window") })"
  fi
}

case "$dispatcher" in
  exec)
    [[ -n $arg ]] && dispatch_exec "$arg"
    ;;
  sendshortcut)
    [[ -n $arg ]] && dispatch_sendshortcut "$arg"
    ;;
  lua)
    [[ -n $arg ]] && hyprctl dispatch "$arg"
    ;;
  "")
    exit 0
    ;;
  *)
    if [[ -n $arg ]]; then
      hyprctl dispatch "$dispatcher" "$arg"
    else
      hyprctl dispatch "$dispatcher"
    fi
    ;;
esac

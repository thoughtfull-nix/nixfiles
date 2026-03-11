#!/usr/bin/env bash
makoctl mode -t dnd &>/dev/null
if makoctl mode | grep dnd &>/dev/null; then
  notify-send -a dnd "Do-not-disturb enabled"
else
  notify-send -a dnd "Do-not-disturb disabled"
fi

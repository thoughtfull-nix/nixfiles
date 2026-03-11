#!/usr/bin/env bash
@pactl@ set-source-volume @DEFAULT_SOURCE@ +5%
vol=$(@pactl@ get-source-volume @DEFAULT_SOURCE@ |
  head -n1 |
  cut -d'/' -f2 |
  sed 's/[^0-9]//g')
pa_vol=$((vol * 65536 / 100))
@paplay@ --volume="${pa_vol}" @mic-volume-pop@
@mic-status@

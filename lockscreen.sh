#!/usr/bin/bash

sudo echo 80 | sudo tee /sys/class/backlight/amdgpu_bl0/brightness &
xscreensaver-command -lock &
sleep 5m
systemctl suspend &

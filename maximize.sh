#!/bin/bash
# resizes the window to full height and width

wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz

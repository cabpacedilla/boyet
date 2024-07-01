#!/usr/bin/sh
# This script will activate screen lock when the laptop lid will be closed for auto lid close security in icewm window manager in Linux
# This script was written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# Steps for the task:
# 1. icewm is already installed and configured for user login
# 2. Install xscreensaver
# 3. Create a bin directory inside your home directory
# 4. Change directory to the bin directory
# 5. Create the bash script file below with nano or gedit and save it with a filename like lid_close.sh
# 6. Make file executable with chmod +x lid_close.sh command
# 7. Add the "lid_close.sh &" command in .icewm/startup script
# 8. Reboot the laptop
# 9. Login to icewm
# 10. Close the laptop lid
# 11. Open the laptop lid
# 12. xscreensaver will ask for password

#!/usr/bin/bash
while true; do

LID_PATH=/proc/acpi/button/lid/LID0/state
HDMI_DETECT=$(xrandr |grep ' connected' |grep 'HDMI' |awk '{print $1}')

## 1. Set for open state
OPEN_STATE="open"

## 2. Get laptop lid state
LID_STATE=$(cat $LID_PATH | awk '{print $2}')

#~ if [ "$(echo $?)" != "0" ]; then
	#~ break
#~ fi

## 3. Lock and suspend if lid is close and do nothing otherwise
if [ "$LID_STATE" = "$OPEN_STATE" ]; then
	:
else
	sudo echo 1000 | sudo tee /sys/class/backlight/amdgpu_bl1/brightness
	xscreensaver-command --lock
	systemctl suspend
	if [ -n "$HDMI_DETECT" ]; then
		sudo echo 1000 | sudo tee /sys/class/backlight/amdgpu_bl1/brightness
		xscreensaver-command --lock
		systemctl suspend
	fi
fi

sleep 0.1s
done





#!/usr/bin/sh
# This script will notify when Caps Lock or Num Lock are on using the xset q command.
# This script was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# October 2020

# Steps for the task:
# 1. Create a bin directory inside your home directory
# 2. Change directory to the bin directory
# 3. Create the bash script file below with nano or gedit and save it with a filename like keyLocked.sh
# 4. Make file executable with chmod +x keyLocked.sh command
# 5. Add the keyLocked.sh command in Startup applications
# 6. Reboot the laptop
# 7. Press the Caps Lock key
# 8. A Caps Lock key notification message will be displayed
# 9. Press the Num Lock key
# 10. A Num Lock key notification message will be displayed

while true
do
# 1. Set key lock values
CAPS_LOCK=00000001
NUM_LOCK=00000002
CAPSNUM_LOCK=00000003
#NO_LOCK=00000000

# 2. Get LED mask value for key lock with xset command
LED_MASK=$(xset q | grep 'LED mask' | awk '{ print $NF }')

if [ "$(echo $?)" != "0" ]; then
	sleep 
fi	

# 3. Compare LED_MASK to key lock values
case "$LED_MASK" in
	"$CAPS_LOCK")
		notify-send -t 9000 --app-name "Key lock:" "Caps lock is on."
		;;
		
	"$NUM_LOCK")
		notify-send -t 9000 --app-name "Key lock:" "Num lock is on."
		;;
		
	"$CAPSNUM_LOCK")
		notify-send -t 9000 --app-name "Key lock:" "Caps lock and Num lock are on."
		;;
		
	*)
		:
		;;
esac

sleep 10
done      

# This script will activate screen lock when the laptop lid will be closed for auto lid close security in Ubuntu Unity
# This script was written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# September 2020

# Steps for the task:
# 1. Install the ligthdm display manager and set lightdm as a the default display manager
# 2. Create a bin directory inside your home directory
# 3. Change directory to the bin directory
# 4. Create the bash script file below with nano or gedit and save it with a filename like lid_closed.sh
# 5. Make file executable with chmod +x lid_closed.sh command
# 6. Add the lid_closed.sh command in Startup applications
# 7. Reboot the laptop
# 8. Close the laptop lid
# 9. Open the laptop lid
# 10. lightdm login screen will be displayed

#!/usr/bin/bash
while true
do
   lid_status=$(less /proc/acpi/button/lid/LID0/state | awk '{print $2}')
   
   if [ "$lid_status" = 'open' ]; then
      :
        
   else
      xscreensaver-command -lock
      systemctl suspend
      
      #dm-tool switch-to-greeter
      #dbus-send --type=method_call --dest=org.gnome.Screensaver /org/gnome/Screensaver org.gnome.ScreenSaver.lock
      
   fi
   
   sleep 1
done

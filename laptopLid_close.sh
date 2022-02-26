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

#!/usr/bin/sh

while true
do
   ## 1. Set 
   OPEN_STATE="open"
   
   ## 2. Get laptop lid state
   LID_STATE=$(less /proc/acpi/button/lid/LID0/state | awk '{print $2}')
   
   ## 3. Do nothing if lid is open
   if [ "$LID_STATE" = "$OPEN_STATE" ]; then
      :
  
  ## 4. Lock screen if lid is closed
   else
      xscreensaver-command -lock
      systemctl suspend
      
      #dm-tool switch-to-greeter
      #dbus-send --type=method_call --dest=org.gnome.Screensaver /org/gnome/Screensaver org.gnome.ScreenSaver.lock
      
   fi
   
   sleep 1
done

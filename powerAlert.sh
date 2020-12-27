
#!/usr/bin/bash
notify()
{
   # set plug or unplug 
   if [ "$1" = low ]; then
        ACTION="Plug"
        
   elif [ "$1" = full ]; then
        ACTION="Unplug"
   fi
    
   # notify to plug or unplug based on battery level
   notify-send -1500 "Battery reached $2%. $ACTION the power cable to optimize battery life!"
   
   # check if cvlc file program is existing then play low or full mp3
   if [ -f "$(which cvlc)" ]; then
      cvlc --play-and-exit ~/Music/battery-"$1".mp3 2>/dev/null
 
   fi
}

while true
do
   battery_level=$(acpi -b | grep -P -o '[0-9]+(?=%)')
   battery_charge=$(acpi -b | grep -P -o Charging)
   battery_discharge=$(acpi -b | grep -P -o Discharging)
   battery_full=$(acpi -b | grep -P -o Full)

   if [ "$battery_level" -le 40 ] && [ "$battery_discharge" = Discharging ]; then
   # call notify function and pass low argument and battery level
      notify low "$battery_level"
      
   elif [ "$battery_level" -le 40 ] && [ "$battery_charge" = Charging ]; then
      :
    
   elif [[ "$battery_level" -ge 80 ] && [ "$battery_charge" = Charging ]] || [[ "$battery_level" -ge 80 ] && [ "$battery_full" = Full ]]; then
   # call notify function and pass full argument and battery level
      notify full "$battery_level"
      
   #elif [ "$battery_level" -ge 80 ] && [ "$battery_full" = Full ]; then
    #  notify full "$battery_level"
     
   #fi
   
   sleep 60
done

#!/usr/bin/bash
while true
do

MIN_ID=1
NO_ID=0

LOWMEM_IDS=$(pgrep -c lowmem)
LOWMEM_PROC=$(pidof -x lowmem.sh)
declare -a LOWMEMARR
IFS=' ' read -r -a LOWMEMARR <<< "$LOWMEM_PROC"   
i=0
  while [ "${LOWMEMARR[$i]}" != "${LOWMEMARR[-1]}" ]; do
  echo "${LOWMEMARR[$i]}"
  if [ "$LOWMEM_IDS" -gt $MIN_ID ]; then
      kill -9 "${LOWMEMARR[$i]}"
      notify-send "lowmem ${LOWMEMARR[$i]} process ID is killed."
  fi
  i=$[$i +1]
  done

if [ "$LOWMEM_IDS" -eq $NO_ID ]; then
	notify-send "Lowmem is not running. Please check if Lowmem process is running" 	  
	if lowmem.sh & then
		notify-send "Lowmem is running"
	fi 
else 
	:
fi

WEATHER_IDS=$(pgrep -c weatheralarm)
WEATHER_PROC=$(pidof -x weatheralarm.sh)
if [ "$WEATHER_IDS" -gt $MIN_ID ]; then
declare -a WEATHERARR
IFS=' ' read -r -a WEATHERARR <<< "$WEATHER_PROC"   
i=0
  while [ "${WEATHERARR[$i]}" != "${WEATHERARR[-1]}" ]; do
  echo "${WEATHERARR[$i]}"
          kill -9 "${WEATHERARR[$i]}"
          notify-send "weatheralarm ${WEATHERARR[$i]} process ID is killed."
          i=$[$i +1]
  done
fi

if [ "$WEATHER_IDS" -eq $NO_ID ]; then
  notify-send "Weatheralarm is not running. Please check if weatheralarm process is running" 
  if  weatheralarm.sh & then
          notify-send "Weatheralarm is running"
  fi      
else 
  :
fi

KEYLOCKED_IDS=$(pgrep -c keylocked)
KEYLOCKED_PROC=$(pidof -x keylocked.sh)
if [ "$KEYLOCKED_IDS" -gt $MIN_ID ]; then
declare -a KEYLOCKARR
IFS=' ' read -r -a KEYLOCKARR <<< "$KEYLOCKED_PROC"   
i=0
while [ "${KEYLOCKARR[$i]}" != "${KEYLOCKARR[-1]}" ]; do
   echo "${KEYLOCKARR[$i]}"
	kill -9 "${KEYLOCKARR[$i]}"
	notify-send "keylocked ${KEYLOCKARR[$i]} process ID is killed."
	i=$[$i +1]
done
fi

if [ "$KEYLOCKED_IDS" -eq $NO_ID ]; then
	notify-send "keylocked is not running. Please check if keylocked process is running" 
	if keylocked.sh & then
		notify-send "keylocked is running"
	fi		
else 
	:
fi

LIDCLOSED_IDS=$(pgrep -c lidclosed)
LIDCLOSED_PROC=$(pidof -x lidclosed.sh)
if [ "$LIDCLOSED_IDS" -gt $MIN_ID ]; then
   declare -a LIDCLOSEDARR
   IFS=' ' read -r -a LIDCLOSEDARR <<< "$LIDCLOSED_PROC"   
   i=0
	while [ "${LIDCLOSEDARR[$i]}" != "${LIDCLOSEDARR[-1]}" ]; do
	   echo "${LIDCLOSEDARR[$i]}"
		kill -9 "${LIDCLOSEDARR[$i]}"
		notify-send "lidclosed ${LIDCLOSEDARR[$i]} process ID is killed."
		i=$[$i +1]
	done
fi

if [ "$LIDCLOSED_IDS" -eq $NO_ID ]; then
	notify-send "lidclosed is not running. Please check if lidclosed process is running" 
	if lidclosed.sh & then
		notify-send "lidclosed is running"
	fi		
else 
	:
fi

BATALERT_IDS=$(pgrep -c battalert)
BATALERT_PROC=$(pidof -x battalert.sh)
if [ "$BATALERT_IDS" -gt $MIN_ID ]; then
   declare -a BATALERTARR
   IFS=' ' read -r -a BATALERTARR <<< "$BATALERT_PROC"   
   i=0
	while [ "${BATALERTARR[$i]}" != "${BATALERTARR[-1]}" ]; do
	   echo "${BATALERTARR[$i]}"
		kill -9 "${BATALERTARR[$i]}"
		notify-send "battalert ${BATALERTARR[$i]} process ID is killed."
		i=$[$i +1]
	done
fi

if [ "$BATALERT_IDS" -eq $NO_ID ]; then
	notify-send "battalert is not running. Please check if battalert process is running" 
	if battalert.sh & then
		notify-send "battalert is running"
	fi		
else 
	:
fi

BRIGHTNESS_IDS=$(pgrep -c brightness)
BRIGHTNESS_PROC=$(pidof -x brightness.sh)
if [ "$BRIGHTNESS_IDS" -gt $MIN_ID ]; then
   declare -a BRIGHTNESSARR
   IFS=' ' read -r -a BRIGHTNESSARR <<< "$BRIGHTNESS_PROC"   
   i=0
	while [ "${BRIGHTNESSARR[$i]}" != "${BRIGHTNESSARR[-1]}" ]; do
	   echo "${BRIGHTNESSARR[$i]}"
		kill -9 "${BRIGHTNESSARR[$i]}"
		notify-send "brightness ${BRIGHTNESSARR[$i]} process ID is killed."
		i=$[$i +1]
	done
fi

if [ "$BRIGHTNESS_IDS" -eq $NO_ID ]; then
	notify-send "brightness is not running. Please check if brightness process is running" 
	if brightness.sh & then
		notify-send "brightness is running"
	fi		
else 
	:
fi

LISTENBACK_IDS=$(pgrep -c backlisten)
LISTENBACK_PROC=$(pidof -x backlisten.sh)
if [ "$LISTENBACK_IDS" -gt $MIN_ID ]; then
   declare -a LISTENBACKARR
   IFS=' ' read -r -a LISTENBACKARR <<< "$LISTENBACK_PROC"   
   i=0
	while [ "${LISTENBACKARR[$i]}" != "${LISTENBACKARR[-1]}" ]; do
	   echo "${LISTENBACKARR[$i]}"
		kill -9 "${LISTENBACKARR[$i]}"
		notify-send "listenback ${LISTENBACKARR[$i]} process ID is killed."
		i=$[$i +1]
	done
fi

if [ "$LISTENBACK_IDS" -eq $NO_ID ]; then
	notify-send "listenback is not running. Please check if listenback process is running"   
	if backlisten.sh & then
		notify-send "listenback is running"
	fi		
else 
	:
fi

AUTOUPDATE_IDS=$(pgrep -c autoupdate)
AUTOUPDATE_PROC=$(pidof -x autoupdate.sh)
if [ "$AUTOUPDATE_IDS" -gt $MIN_ID ]; then
  	declare -a AUTOUPDATEARR
  	IFS=' ' read -r -a AUTOUPDATEARR <<< "$AUTOUPDATE_PROC"   
  	i=0
	while [ "${AUTOUPDATEARR[$i]}" != "${AUTOUPDATEARR[-1]}" ]; do
   	echo "${AUTOUPDATEARR[$i]}"
		kill -9 "${AUTOUPDATEARR[$i]}"
		notify-send "listenback ${AUTOUPDATEARR[$i]} process ID is killed."
		i=$[$i +1]
	done
fi

if [ "$AUTOUPDATE_IDS" -eq $NO_ID ]; then
   notify-send "autoupdate is not running. Please check if autoupdate process is running" 
   if autoupdate.sh & then
		notify-send "autoupdate is running"
	fi
else
	:
fi

sleep 1s
done

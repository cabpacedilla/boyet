#!/usr/bin/bash
# This script will rip audio parts from a video file with ffmpeg using their start times and duration times
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.

FORMAT=$(file "$1" | awk '{print $4}')
declare -a starttimes durations titles

starttimes=(0:00:00 0:03:02 0:7:15 0:11:32 0:15:32 0:18:51 0:22:21 0:26:27 0:31:25 0:34:50 0:37:32 0:40:23 0:44:04 0:48:42 0:50:54 0:55:06 0:58:14 0:60:33 59:58:06 1:03:22 1:06:51 1:10:35 1:14:23 1:17:35 1:22:42 1:25:18 1:29:43 1:34:37 1:38:11 1:42:34 1:46:20)

durations=(0:03:02 0:04:13 0:04:17 0:04:00 0:03:19 0:03:30 0:04:06 0:04:58 0:03:25 0:02:42 0:02:51 0:03:41 0:04:38 0:02:12 0:04:12 0:03:08 0:03:17 0:02:29 0:01:22 0:01:29 0:03:44 0:03:48 0:03:12 0:05:07 0:02:36 0:04:25 0:04:54 0:03:34 0:04:23 0:03:46 0:09:45)

titles=("River Flows in You" "Kiss the Rain" "Spring Time" "May Be" "When the Love Falls" "Because I Love You" "Love Me" "Time Forget..." "If I Could See You Again" "Fairy Tale" "Hope" "It's Your Day" "Passing By" "Dream A Little Dream Of Me" "I..." "The Days That'll Never Come" "Reminiscent" "Farewell" "Sky" "Painted" "Till I Find You" "Poem" "Left My Heart" "Indigo" "Piano P.N.O.N.I" "Wait There" "Tears on Love" "Inside the Memories" "Yellow Room" "With the Wind")

echo "Which audio format would you like to save the songs with, mp3 or m4a?"
read -r FORMAT

s=0
d=0
t=0 

while [ "${starttimes[$s]}" != "${starttimes[-1]}" ]  &&  [ "${durations[$d]}" != "${durations[-1]}" ]  &&  [ "${titles[$t]}" != "${titles[-1]}" ] ; do
    
    if [ "$FORMAT" = "mp3" ] || [ "$FORMAT" = "MP3" ]; then
      ffmpeg -y -i "$1" -ss "${starttimes[$s]}" -t "${durations[$d]}" -q:a 0 -map a "${titles[$t]}".mp3
    
    elif [ "$FORMAT" = "m4a" ] || [ "$FORMAT" = "M4A" ]; then
      ffmpeg -y -i "$1" -ss "${starttimes[$s]}" -t "${durations[$d]}" -vn -c:a copy -map a "${titles[$t]}".m4a
    
    fi

    s=$[$s +1]
    d=$[$d +1]
    t=$[$t +1]
done

notify-send "Audio rip alert!" "Audtio rip is done."
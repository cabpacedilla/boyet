#!/usr/pkg/bin/bash
# This script will rip audio parts from a video file with ffmpeg using their start times and duration times
# This code was assembled and written by Claive Alvin P. Acedilla. It can be copied, modified and redistributed.
# July 2020

declare -a starttimes durations titles

starttimes=(0:00:00 0:03:02 0:7:15 0:11:32 0:15:32 0:18:51 0:22:21 0:26:27)

durations=(0:03:02 0:04:13 0:04:17 0:04:00 0:03:19 0:03:30 0:04:06)

titles=(Track1 Track2 Track3 Track4 Track5 Track6 Track7)

# initialize startime, duration and title counters
sCtr=0
dCtr=0
tCtr=0 

# Loop startimes, durations and titles array with ffmpeg to rip audio from file
while [ "${starttimes[$sCtr]}" != "${starttimes[-1]}" ]  &&  [ "${durations[$dCtr]}" != "${durations[-1]}" ]  &&  [ "${titles[$tCtr]}" != "${titles[-1]}" ] ; do
    ffmpeg4 -y -i /home/cabpa/video.mkv -ss "${starttimes[$s]}" -t "${durations[$d]}" -q:a 0 -map a "${titles[$t]}".mp3
    s=$($sCtr +1)
    d=$($dCtr +1)
    t=$($tCtr +1)
done

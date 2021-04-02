#!/usr/pkg/bin/bash

PATH=$HOME/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R7/bin:/usr/pkg/bin
PATH=${PATH}:/usr/pkg/sbin:/usr/games:/usr/local/bin:/usr/local/sbin
export PATH

PKG_PATH="https://ftp.netbsd.org/pub/pkgsrc/packages/NetBSD/$(uname -p)/$(uname -r | cut -d_ -f1)/All"
export PKG_PATH

PS1='\u@\h \w\$ '

declare -a ANIMALS
ANIMALPATH=/usr/pkg/share/cows/
EXT=.cow

ANIMALS=(beavis.zen blowfish bong bud-frogs bunny cheese cower daemon default dragon-and-cow dragon elephant-in-snake elephant eyes flaming-sheep ghostbusters head-in hellokitty kiss kitty koala kosh luke-koala meow milk moofasa moose mutilated ren satanic sheep skeleton small sodomized stegosaurus stimpy supermilker surgery telebears three-eyes turkey turtle tux udder vader-koala vader www)

RANDANIMAL=${ANIMALS[$RANDOM % ${#ANIMALS[@]}]}

exec /usr/games/fortune | /usr/pkg/bin/cowsay -f ${ANIMALPATH}${RANDANIMAL}${EXT}


#!/bin/sh
cd "${0%/*}" || exit 1
read -p "⚙️ Please enter the password (plaintext) and press Enter: " -r passwd
printf "\r\033[1A%s" "" 1>&2
printf "\r\033[K%s" "" 1>&2
find . -name "*.*" 2>/dev/null | xargs otool -l 2>/dev/null | grep -E "(minos|sdk)" 2>/dev/null
echo "${passwd}" | sudo -S echo "⚙️ Current user is $(sudo -S whoami)"
sudo -S ruby main.rb

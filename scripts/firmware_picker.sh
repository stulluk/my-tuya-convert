#!/bin/bash

MAGIC=$(printf "\xe9")

# Optional non-interactive mode (useful for scripted / CI-style runs).
# When set to a numeric option index (same as the menu), the picker will
# automatically confirm flashing that firmware.
AUTO_FLASH_INDEX="${AUTO_FLASH_INDEX:-}"

while true; do
	echo
	echo "Available options:"
	echo "  0) return to stock"
	index=0
	for file in ../files/*.bin; do
		# skip null glob
		[[ -e $file ]] || continue
		# get short name
		filename=$(basename "$file")
		# skip files too large or too small
		filesize=$(stat -Lc%s "$file")
		[[ "$filesize" -gt 0x1000 && "$filesize" -le 0x80000 ]] || continue
		# skip files without magic byte
		[[ $(head -c 1 "$file") == "$MAGIC" ]] || continue
		echo "  $((++index))) flash $filename"
		options[$index]="$filename"
		# only show first 9 options, accessible with a single keypress
		if (( index == 9 )); then
			break
		fi
	done
	echo "  q) quit; do nothing"
	echo -n "Please select 0-$index: "
	if [[ -n "$AUTO_FLASH_INDEX" ]]; then
		REPLY="$AUTO_FLASH_INDEX"
		echo "$REPLY"
		if [[ ! "$REPLY" =~ ^[0-9]$ || "$REPLY" -lt 0 || "$REPLY" -gt $index ]]; then
			echo "Invalid AUTO_FLASH_INDEX=$AUTO_FLASH_INDEX (valid range: 0-$index)"
			exit 1
		fi
	else
		while true; do
			read -n 1 -r
			echo
			if [[ "$REPLY" =~ ^[0-9]$ && "$REPLY" -ge 0 && "$REPLY" -le $index ]]; then
				break
			fi
			if [[ "$REPLY" =~ ^[Qq]$ ]]; then
				echo "Leaving device as is..."
				exit
			fi
			echo -n "Invalid selection, please select 0-$index: "
		done
	fi

	if [[ "$REPLY" == 0 ]]; then
		if curl -s http://10.42.42.42/undo; then
			echo "Disconnect the device to prevent it from repeating the upgrade"
			echo "You will need to put the device back into pairing mode and register to use again"
		else
			echo "Could not reach the device!"
		fi
		break
	fi

	selection="${options[$REPLY]}"
	if [[ -n "$AUTO_FLASH_INDEX" ]]; then
		echo "AUTO_FLASH_INDEX is set; proceeding to flash $selection without confirmation prompt."
		REPLY="y"
	else
		read -p "Are you sure you want to flash $selection? This is the point of no return [y/N] " -n 1 -r
		echo
		[[ "$REPLY" =~ ^[Yy]$ ]] || continue
	fi

	echo "Attempting to flash $selection, this may take a few seconds..."
	RESULT=$(curl -s "http://10.42.42.42/flash?url=http://10.42.42.1/files/$selection") ||
	echo "Could not reach the device!"

	echo "$RESULT"
	if [[ "$RESULT" =~ failed || -z "$RESULT" ]]; then
		if [[ -n "$AUTO_FLASH_INDEX" ]]; then
			echo "AUTO_FLASH_INDEX is set; not prompting for retries."
			break
		fi
		read -p "Do you want to try something else? [y/N] " -n 1 -r
		echo
		[[ "$REPLY" =~ ^[Yy]$ ]] || break
	else
		if [[ "$selection" == "tasmota.bin" ]]; then
			echo "Look for a tasmota-xxxx SSID to which you can connect and configure"
			echo "Be sure to configure your device for proper function!"
		elif [[ "$selection" == "espurna.bin" ]]; then
			echo "Look for an ESPURNA-XXXXXX SSID to which you can connect and configure"
			echo "Default password is \"fibonacci\""
			echo "Be sure to upgrade to your device specific firmware for proper function!"
		fi
		echo
		echo "HAVE FUN!"
		break
	fi
done


#!/bin/bash
# Usage: onboard_tasmota_plug.sh <tasmota_ap_ssid> <device_name> <expected_lan_ip>
# Joins the plug's open AP, sends Module/name/Wi-Fi settings, waits for it on the LAN,
# verifies, and removes the temporary NetworkManager profile. Never prints the Wi-Fi password.
set -u
set +x
AP_SSID="$1"; NAME="$2"; LAN_IP="$3"; IF="wlp8s0"
OUT="$(dirname "$0")/cm_out_${NAME}.txt"
PW=$(sed -n 's/^STEW-24-WIFI-PWD=//p' /etc/environment | head -n1)
PW=${PW#\"}; PW=${PW%\"}
[ -n "$PW" ] || { echo "ERROR: password not found"; exit 1; }
echo "password loaded: ${#PW} chars"
echo "== connecting $IF to $AP_SSID"
nmcli dev wifi rescan ifname "$IF" 2>/dev/null; sleep 3
ok=0
for _ in 1 2 3 4; do
  if nmcli -w 30 dev wifi connect "$AP_SSID" ifname "$IF" >/dev/null 2>&1; then ok=1; break; fi
  echo "connect retry..."; sleep 5; nmcli dev wifi rescan ifname "$IF" 2>/dev/null; sleep 4
done
[ "$ok" = 1 ] || { echo "ERROR: wifi connect failed"; exit 1; }
ip -br addr show "$IF"
got=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -s --connect-timeout 2 -m 4 --interface "$IF" "http://192.168.4.1/cm?cmnd=Status%202" -o "$OUT"; then got=1; break; fi
  sleep 2
done
[ "$got" = 1 ] || { echo "ERROR: plug AP not answering"; nmcli connection delete "$AP_SSID" >/dev/null 2>&1; exit 1; }
echo "== plug firmware: $(cat "$OUT")"
echo "== sending Backlog"
curl -sG --connect-timeout 3 -m 8 --interface "$IF" \
  --data-urlencode "cmnd=Backlog Module 49; DeviceName ${NAME}; FriendlyName1 ${NAME}; Hostname ${NAME}; SSID1 STEW-24; Password1 ${PW}" \
  "http://192.168.4.1/cm" -o "$OUT"
echo "curl rc=$? response: $(sed 's/"Password1":"[^"]*"/"Password1":"<hidden>"/g' "$OUT")"
echo "== waiting for $LAN_IP"
up=0
for n in $(seq 1 40); do
  sleep 3
  if ping -c1 -W1 "$LAN_IP" >/dev/null 2>&1; then echo "$LAN_IP UP after ~$((n*3)) s"; up=1; break; fi
done
nmcli connection delete "$AP_SSID" >/dev/null 2>&1 && echo "NM profile $AP_SSID deleted"
[ "$up" = 1 ] || { echo "ERROR: $LAN_IP not up after 120 s"; exit 1; }
sleep 3
echo "== verify from LAN"
curl -s -m 5 "http://${LAN_IP}/cm?cmnd=Status%200" | python3 -I -c '
import json,sys
d=json.load(sys.stdin)
print("Module      :",d["Status"]["Module"], d["Status"]["DeviceName"], d["Status"]["FriendlyName"])
print("Version     :",d["StatusFWR"]["Version"])
print("Hostname/IP :",d["StatusNET"]["Hostname"], d["StatusNET"]["IPAddress"], d["StatusNET"]["Mac"])
print("Wifi        :",d["StatusSTS"]["Wifi"]["SSId"], "RSSI", d["StatusSTS"]["Wifi"]["RSSI"])
print("POWER       :",d["StatusSTS"]["POWER"])'
echo "Module name : $(curl -s -m 5 "http://${LAN_IP}/cm?cmnd=Module")"
echo "DNS         : $(dig +short +time=3 "${NAME}.lan" @192.168.1.25)"

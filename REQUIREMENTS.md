# Neo Coolcam plugs to Tasmota with Docker tuya-convert (October 2026 run)

Status: DONE on 2026-10-24. This file records what was decided and what was actually done,
so the next plug can be converted the same way.

## 1. Goal and decisions

- Convert the remaining Neo Coolcam (Szneo, ESP8266, 1 MB flash) Wi-Fi plugs from stock Tuya
  firmware to Tasmota **without a Raspberry Pi**, using the Docker flow documented in
  `docs/tuya_convert_2026_debian_docker.md` and the April 2026 blog update.
- Keep the plugs identical to the seven plugs converted in 2021-2026: Tasmota **9.2.0(lite)**
  (the `files/tasmota.bin` bundled here), `Module 49` (Neo Coolcam), no MQTT.
- **No OTA server, no custom firmware.** This was the original idea (see git history of this
  file) and was dropped: the stock 9.2.0 plugs work fine and need nothing beyond the one-time
  Wi-Fi + module setup. Tasmota facts gathered while evaluating it are kept in section 6.
- **No Wi-Fi credentials baked into firmware.** Reason: the 40 s button hold resets to firmware
  defaults; with a baked SSID the plug would never fall back to its own AP after a move. Keeping
  credentials in settings preserves the recovery path (6 short presses or 40 s hold ->
  `tasmota_XXXXXX-NNNN` AP -> 192.168.4.1).
- Naming / addressing: Pi-hole v5 on `khadas` (192.168.1.25) hands out static leases from
  `/etc/dnsmasq.d/04-pihole-static-dhcp.conf`; rule `tasmota-N = 192.168.1.(150+N)`.
  Shell aliases `tasmotaN-on` / `tasmotaN-off` live in `~/.bashrc` and curl `http://tasmota-N.lan/cm`.

## 2. Host prerequisites (this PC, Debian, kernel 7.0, Wi-Fi WCN785x `wlp8s0`)

- Wired Ethernet up; Wi-Fi is taken over by hostapd inside the container.
- `config.txt`: `WLAN=wlp8s0`.
- `scripts/eula_accepted` present (gitignored) so the container does not prompt for the EULA.
- **UDP/TCP 53 must be free on the host.** A stray `dnsmasq.service` (installed for the
  Serial-Auto-Test lab, default config) blocked the first run with
  `Checking UDP port 53... Occupied by unknown process` (the container cannot see host PIDs, so
  it cannot offer to kill it). Fixed with `sudo systemctl disable --now dnsmasq`; host DNS is
  Pi-hole, not localhost, so nothing else depends on it.
- The container runs `systemctl stop NetworkManager`, which does nothing in Alpine; it still
  works, but after each run `wlp8s0` keeps the `10.42.42.1/24` address and must be cleaned:
  `sudo ip addr del 10.42.42.1/24 dev wlp8s0`.

## 3. Flash procedure (per plug, about one minute)

```bash
docker build -t tuya-convert:local .
docker run --rm -it --privileged --network host \
  -e WLAN=wlp8s0 -e AP=vtrust-flash -e GATEWAY=10.42.42.1 \
  -e AUTO_FLASH_INDEX=2 -e AUTO_FLASH_ANOTHER_DEVICE=n \
  -v /media/KINGDATA/DREJO-PROJECTS/tuya-convert-deneme/data/backups:/usr/bin/tuya-convert/backups \
  tuya-convert:local
```

1. Phone joins `vtrust-flash` (open AP) and stays there.
2. Plug the device in **while holding the button** until the LED blinks **fast** (Tuya EZ mode).
   Slow blink = Tuya AP mode, smartconfig will not work; hold again to toggle.
3. Press ENTER in the container. Then **do not touch the button** for two minutes.
4. Observed timings: smartconfig to `10.42.42.42` about 25-30 s, 1 MiB backup about 3.5 s
   (290 KB/s), flash `Flashed ... successfully in 8.7-9.1 s`. Backups land in
   `data/backups/<timestamp>/firmware-<chipid>.bin` + `device-info.txt`.
5. Failure seen once (tasmota-11): a second button hold during the upgrade phase makes the stock
   firmware report `s.gw.reset` and drop off before fetching `upgrade.bin`. Logs to read inside
   the running container: `scripts/smarthack-{wifi,web,mqtt,udp,psk}.log`.

Add `-e AUTO_CONTINUE_ON_PARTIAL_BACKUP=y` when a backup is known to be impossible.

## 4. Onboarding (no phone needed)

`scripts/onboard_tasmota_plug.sh <tasmota_ap_ssid> <name> <lan_ip>` joins the plug's open
Tasmota AP from `wlp8s0`, sends one `Backlog` (`Module 49; DeviceName; FriendlyName1; Hostname;
SSID1 STEW-24; Password1`) to 192.168.4.1, waits for the plug on the LAN, verifies `Status 0`,
and deletes the temporary NetworkManager profile. The Wi-Fi password is read from
`/etc/environment` (`STEW-24-WIFI-PWD="..."`) and is never printed. The plug joins the LAN
6-9 s after the Backlog. Before running it: add the Pi-hole `dhcp-host` line and
`pihole restartdns` (keep backups OUT of `/etc/dnsmasq.d/`, dnsmasq reads every file there).

## 5. Result (2026-10-24)

| Name | IP | MAC | Backup | Note |
|---|---|---|---|---|
| tasmota-10 | 192.168.1.160 | DC:4F:22:38:BB:B8 | full 1 MiB | first try |
| tasmota-11 | 192.168.1.161 | DC:4F:22:38:B8:56 | full 1 MiB | second try (button) |
| tasmota-12 | 192.168.1.162 | DC:4F:22:38:B8:46 | full 1 MiB | first try |
| tasmota-13 | 192.168.1.163 | DC:4F:22:38:BC:45 | partial (13 KB) | recovered "bricked" plug |

All four: Tasmota 9.2.0(lite), Module 49 Neo Coolcam, STEW-24, verified with `Status 0`,
`tasmotaN-on/off`, and `tasmota-N.lan` resolution. `alloff` / `allon` aliases include 10-13.

### 5.1 Recovering the "bricked" plug (tasmota-13)

The plug marked "broke during tuya-convert" was not dead: it was still running tuya-convert's
**intermediate firmware** (VTRUST-FLASH 1.5, from `vtrust-de/esp8266-ota-flash-convert`). That
firmware drives no LED and no relay. At boot it tries the open SSID `vtrust-flash` for 20 s with
static IP 10.42.42.42; on failure it opens its own open AP **`vtrust-recovery`** (device still
10.42.42.42) and serves `/`, `/backup`, `/flash?url=`, `/undo`.

- Over `vtrust-recovery` (AP mode) every long transfer died after 3-15 KB: four `/backup`
  attempts and one `/flash` attempt (PC served `tasmota.bin` with `python3 -m http.server`).
  Its AP also hands out no DHCP lease reliably; a static 10.42.42.x on the PC works.
- Over `vtrust-flash` (STA mode): start the container, power-cycle the plug with no button, it
  appeared at 10.42.42.42 after 52 s, and
  `curl "http://10.42.42.42/flash?url=http://10.42.42.1/files/tasmota.bin"` succeeded in 8.9 s.
  The stock backup could not be taken; the partial file is kept as
  `data/backups/recovery_*/firmware-38bc45.bin.PARTIAL`.
- After Tasmota came up the LED and relay work normally.

## 6. Tasmota facts kept for reference (OTA idea, not implemented)

- Latest release v16.0.0 (2026-10-16) still supports 1M ESP8266; 9.1+ -> current is a direct
  gz OTA. Images larger than free flash trigger the automatic `<name>-minimal.bin.gz` step.
- `Upgrade 1` always flashes `OtaUrl`; `Upgrade x.y.z` flashes only if newer than running.
- No built-in boot-time OTA check; a pull model needs rules + `WebQuery` + a custom build with
  `USE_WEBSEND_RESPONSE`. A push model (server sends `Upgrade 1`) needs nothing custom.
- tuya-convert can only flash images <= 512 KB with bootloader, so a modern Tasmota would have
  to go in as a second OTA step after 9.2.0.

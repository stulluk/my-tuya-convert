# Tuya-Convert on a Debian desktop (Docker) — what we did (2026)

This document summarizes a successful `tuya-convert` run migrating a Tuya/SmartLife Neo-style Wi‑Fi plug to **Tasmota**, but this time on a **Debian host PC** using **Docker**, compared to an older Raspberry Pi workflow.

## Host hardware / software snapshot (this PC)

- **OS / kernel**: Debian (kernel `6.19.11+deb14-amd64`, `PREEMPT_DYNAMIC`, `x86_64`)
- **Wi‑Fi chipset**: Qualcomm **WCN785x** (PCI ID `17cb:1107`, subsystem `105b:e0f7`)
- **Wi‑Fi driver**: `ath12k_pci`
- **Wi‑Fi interface**: `wlp8s0`
- **Ethernet**: host had a wired connection during the attempt (recommended for stability while Wi‑Fi is repurposed as an AP)
- **Docker**: `Docker 28.5.2+dfsg3`

## What we set up

- Cloned upstream `tuya-convert` into this workspace:
  - Repo: `https://github.com/ct-Open-Source/tuya-convert`
- Configured Wi‑Fi interface name in `config.txt`:
  - `WLAN=wlp8s0` (the stock template used `wlan0`, which did not exist on this machine)
- Built and ran the upstream Docker image:
  - `docker build -t tuya-convert:local .`
  - `docker run --rm --privileged --network host ... tuya-convert:local`

Notes:

- This machine did not have the `docker compose` plugin nor `docker-compose` binary; we used plain `docker build` / `docker run`, which is equivalent for this project.

## Problems encountered and how we solved them

### 1) Wrong WLAN interface in `config.txt`

**Symptom**: setup checks failed because it looked for `wlan0`.

**Fix**: set `WLAN=wlp8s0` in `config.txt` and rebuild the Docker image so the container contains the updated config.

### 2) Phone could not connect to `vtrust-flash`

**Symptom**: phone reported it could not connect/join the AP.

**Likely causes / mitigations**:

- AP is **internet-less** by design; phones often need “stay connected / don’t switch to mobile data”.
- Randomized MAC / Wi‑Fi assistant features can interfere on some phones.
- During failures, it’s worth verifying the AP is truly up (host had `10.42.42.1/24` on `wlp8s0` while services were running).

### 3) First attempts timed out at SmartConfig / no ESP association

**Symptom**: repeated SmartConfig retries; diagnosis path indicated no ESP82xx association.

**What changed on the successful path**: once the phone stayed connected to `vtrust-flash` and the plug was in the correct fast-blink pairing mode, the device progressed.

### 4) Non-interactive automation got stuck at `firmware_picker.sh`

**Symptom**: after the device reached `10.42.42.42`, the script waited for a keypress (`Please select 0-2:`) and stdin was not a real TTY, producing endless `Invalid selection`.

**Fix**: added small, explicit automation hooks:

- `scripts/firmware_picker.sh`: `AUTO_FLASH_INDEX` to auto-select a firmware menu index and skip the “are you sure” prompt in automated runs.
- `start_flash.sh`: `AUTO_FLASH_ANOTHER_DEVICE` and `AUTO_CONTINUE_ON_PARTIAL_BACKUP` to avoid blocking prompts in scripted runs.

With:

- `AUTO_FLASH_INDEX=2` (Tasmota option in the menu we saw)
- `AUTO_FLASH_ANOTHER_DEVICE=n`

…the flash completed successfully:

- `Flashed http://10.42.42.1/files/tasmota.bin successfully ... rebooting...`

## Operational checklist (short)

- Prefer **wired Ethernet** on the host while flashing.
- Put phone on **`vtrust-flash`** and keep it connected.
- Put device in **fast blink** smartconfig/pairing mode.
- After success, configure Tasmota via its **`tasmota-xxxx`** AP / `192.168.4.1`.

## Caveats / expectations

- `tuya-convert` is **not universally reliable** on modern Wi‑Fi chipsets; this WCN785x/`ath12k` path worked here, but USB AP-capable adapters are still the “safe default” in the community.
- Many newer Tuya devices are patched or not ESP-based; always verify chip/module expectations before assuming Tasmota compatibility.

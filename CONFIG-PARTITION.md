# TC8 autoconfigure — the `cache`-partition config blob (v1)

How the provisioning wizard pushes device configuration to a TC8 **over
fastboot**, with no bootloader change. The wizard writes a small blob to the
stock **`cache`** GPT partition; a boot-time service applies it before the kiosk
starts. This doc is the contract: the **Linux half is implemented** (in this
repo); the **web/wizard half** (build + flash the blob) implements against the
format below.

## Why `cache`
- It's in the stock Android GPT — **1 GiB ext4** (was Android `/cache`), **unused**
  by our Debian. (Confirmed on a live v0.4.x unit: `/dev/mmcblk2p7`, clean, 95% free.)
- `fastboot flash cache <blob>` works with the **existing stage-2 fastboot** — no
  bootloader rebuild, no re-enroll.
- `cache` is **not** in the AVB-verified chain (`boot`/`dtbo`/`vbmeta`) → **no re-sign**.
- Legacy flat-layout units have no `cache`; the reader no-ops there until they're
  re-flashed to the v0.4.x stock-GPT model.

## Blob format
Written to the **start** of the `cache` partition. All integers little-endian.

| offset | size | field |
|-------:|-----:|-------|
| 0  | 8  | magic = ASCII `"TC8CFGv1"` |
| 8  | 4  | `length` — payload byte length (u32 LE) |
| 12 | 32 | `sha256(payload)` — raw 32 bytes |
| 44 | 20 | reserved (zero) |
| 64 | N  | payload |

- **payload** — UTF-8 text, one `KEY=value` per line (LF). `#` and blank lines
  ignored. `length` = payload byte count. Max **1 MiB**.
- The device verifies **magic + sha256** before applying. A fresh/empty `cache`
  (no magic) or a corrupt/half-written blob is **ignored** — the unit keeps its
  current config. Applied **every boot** (idempotent); the blob is not cleared.
- The blob can be tiny (header + payload); fastboot writes it to the partition
  start, no need to write the whole 1 GiB.

## Building the blob (web/wizard half)
```js
const enc = new TextEncoder();
const payload = enc.encode(lines.join("\n") + "\n");          // "KEY=value\n..."
const sha = new Uint8Array(await crypto.subtle.digest("SHA-256", payload));
const head = new Uint8Array(64);
head.set(enc.encode("TC8CFGv1"), 0);                          // magic
new DataView(head.buffer).setUint32(8, payload.length, true); // length LE
head.set(sha, 12);                                            // sha256
const blob = new Uint8Array(head.length + payload.length);
blob.set(head, 0); blob.set(payload, 64);
// fastboot flash cache <blob>  ;  fastboot reboot
```

## Config keys (the autoconfigure schema)
Status: **✅ implemented** in the v1 reader (`rootfs/etc/tc8-config/apply-config.sh`);
**▢ planned** (reserved key — document + implement incrementally).

### Identity
| key | st | effect | example |
|-----|----|--------|---------|
| `DEVICE_NAME` | ✅ | `/etc/hostname` + `hostname` | `lobby-east` |
| `LOCATION` | ▢ | inventory label (motd / a `/etc/tc8-location`) | `Bldg A / Lobby` |

### Kiosk / display
| key | st | effect | example |
|-----|----|--------|---------|
| `KIOSK_URL` | ✅ | `/etc/default/tc8-kiosk` `KIOSK_URL=` (web page **or** `rtsp://…`) | `https://dash.local` |
| `KIOSK_URL_FALLBACK` | ✅ | secondary URL if primary unreachable | `https://backup.local` |
| `COG_OPTS` | ✅ | cog browser flags | `--enable-media=true` |
| `ROTATION` | ▢ | panel orientation override (cage `-r` count) | `1` |
| `BLANK_TIMEOUT` | ▢ | screen-blank / DPMS seconds (0 = always on) | `0` |
| `BRIGHTNESS` | ▢ | backlight 0–100 | `80` |
| `RELOAD_INTERVAL` | ▢ | periodic kiosk reload / crash-watchdog (s) | `3600` |

### Network
| key | st | effect | example |
|-----|----|--------|---------|
| `NET_MODE` | ▢ | `dhcp` \| `static` (writes systemd-networkd) | `static` |
| `IP_ADDR` / `NETMASK` / `GATEWAY` | ▢ | static addressing | `192.168.1.50/24` |
| `DNS` | ▢ | resolvers (comma list) | `192.168.1.1,1.1.1.1` |
| `VLAN_ID` | ▢ | tag the `lan` port (DSA switch supports it) | `40` |
| `HTTP_PROXY` | ▢ | proxy for kiosk + updates | `http://proxy:3128` |
| `NTP_SERVER` | ✅ | `timesyncd.conf` `NTP=` | `192.168.1.1` |

### Access / credentials
| key | st | effect | example |
|-----|----|--------|---------|
| `ROOT_PASSWORD` | ✅ | `chpasswd` for `root` (change the default `root/root`!) | `s3cret` |
| `KIOSK_PASSWORD` | ✅ | `chpasswd` for the `kiosk` user | `…` |
| `SSH_AUTHKEY` | ✅ | append to `/root/.ssh/authorized_keys` (fleet admin access) | `ssh-ed25519 AAAA…` |
| `SSH_ENABLE` | ▢ | enable/disable sshd | `true` |
| `SSH_PASSWORD_AUTH` | ▢ | allow/deny password login (harden) | `false` |
| `STREAM_USER` / `STREAM_PASS` | ▢ | creds for the kiosk destination if not embedded in the URL (e.g. RTSP camera) | `admin` / `…` |

### Certificates / trust
| key | st | effect | example |
|-----|----|--------|---------|
| `CA_CERT_B64` | ✅ | base64 PEM → `/usr/local/share/ca-certificates/fleet-N.crt` + `update-ca-certificates` (trust internal HTTPS/RTSP CAs). Repeatable. | `LS0tLS1CRUdJ…` |
| `CLIENT_CERT_B64` / `CLIENT_KEY_B64` | ▢ | mTLS client cert/key to the destination | `…` |

### Time / locale / audio
| key | st | effect | example |
|-----|----|--------|---------|
| `TIMEZONE` | ✅ | `/etc/localtime` + `/etc/timezone` | `America/New_York` |
| `LOCALE` | ▢ | system locale | `en_US.UTF-8` |
| `VOLUME_MASTER` / `VOLUME_SPEAKER` | ✅ | `amixer` caps (small panel speakers distort high) | `80` / `75` |

### Management / ops
| key | st | effect | example |
|-----|----|--------|---------|
| `LOG_FORWARD` | ▢ | remote syslog endpoint | `udp://logs:514` |
| `HEARTBEAT_URL` | ▢ | health/telemetry beacon | `https://fleet/beat` |
| `OTA_CHANNEL` / `OTA_URL` | ▢ | update channel + server | `stable` |
| `REBOOT_SCHEDULE` | ▢ | nightly reboot (kiosk hygiene), cron/timer | `04:00` |

> Multi-line / binary values (certs, keys) travel **base64-encoded** in the
> `*_B64` keys — keeps the payload single-line `KEY=value`. Unknown keys are
> logged and ignored, so the wizard can send a superset safely.

## Precedence & flows
- **Precedence:** the `cache` blob is the **base**; a local `/data/poly-kiosk/config`
  file (existing `kiosk-config.service`) still **overrides** it. So a hands-on
  local edit beats the last pushed config.
- **Reconfigure** (already-unlocked unit): 4-finger → fastboot → wizard builds the
  blob from the form → `fastboot flash cache` → `fastboot reboot`.
- **Unlock / Reinstall:** flash a **default** blob so a fresh unit boots configured.

## Security
The blob is **plaintext at rest** on `cache` (any root user on the device can read
it — passwords, keys). That's usually acceptable for a trusted-fleet config, and
it travels over **local USB/fastboot**, not the network. If a deployment needs
secrets protected at rest, that's a v2 item (encrypt the payload to a device/fleet
key). Don't put anything in here you wouldn't accept on the device's disk.

## Linux side (implemented here)
- `rootfs/etc/tc8-config/apply-config.sh` — POSIX-sh reader (busybox/coreutils only).
- `rootfs/etc/systemd/system/tc8-config.service` — oneshot, `Before=kiosk-config.service kiosk.service`.
- Enabled in `rootfs/chroot-setup.sh`. To add a `▢` key: extend the reader's
  `case`, flip it to ✅ here.

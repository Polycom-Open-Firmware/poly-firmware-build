# tc8-firmware-build

Sideload mainline Linux + a Debian kiosk onto the **Polycom TC8**
video-conferencing touch panel (i.MX 8M Mini, codename LCC). Build a
reproducible image, push it to a panel, repurpose the hardware. Display,
touch, audio, network, USB gadget, netboot, and the browser-provisioner
install path are all verified end-to-end on hardware.

**How it works** — the SoC's HAB fuses pin stock U-Boot's signature, so we
never replace it. A one-time **enroll** lands our stage-2 U-Boot in the
eMMC `boot1` hardware partition; stock stage-1 chainloads it, and — with
the bootloader unlocked — stage-2 boots Debian as a slotable A/B
Android image using NXP `boota`, carrying AVB metadata that is
structurally valid but unsigned. [FLASHING.md](FLASHING.md) has the mechanics.

**How it's installed** — the
[browser provisioner](https://github.com/Polycom-Open-Firmware/provisioner)
(WebUSB: no host `fastboot` binary, no driver install). A fresh unit takes
a one-time serial bootstrap to force fastboot; from then on it's the
four-finger gesture and the browser. [QUICKSTART.md](QUICKSTART.md) walks
through it.

## What you get on the panel

- 800×1280 DSI panel + backlight, etnaviv GC600/GC520 GPU acceleration
- Goodix GT9110 multi-touch (`/dev/input/event0`)
- TAS5751M class-D audio amplifier on SAI1 (`tas5751-audio` ALSA card; default volume capped at Master 80% / Speaker 75% — small panel speakers distort past that)
- RTL8363NB-VB DSA switch + FEC ethernet (`lan` interface, 1 Gbps full-duplex)
- Composite USB gadget on the data port: CDC ACM (`/dev/ttyACM0` with a root login), CDC NCM (USB Ethernet, panel at `10.55.0.1`, ssh straight off the cable), and MTP (`/data` exposed as a "Portable Device" for drag-and-drop)

Everything boots into a fullscreen Wayland kiosk (`cage` + `cog`) — by
default a bundled touch-tester; point `KIOSK_URL` at any page you like
([USING.md](USING.md)).

## Quick start

**Just want a kiosk?** No build needed — the provisioner ships the release
artifacts. Follow [QUICKSTART.md](QUICKSTART.md).

**Build from source:**

```bash
git clone --recurse-submodules https://github.com/Polycom-Open-Firmware/tc8-firmware-build.git
cd tc8-firmware-build
./bootstrap.sh
sudo ./build.sh --profile=emmc     # → out/emmc/
```

See [BUILDING.md](BUILDING.md) for host setup, credential overrides
(default is **`root` / `root`** — change it), profiles, and iteration
flags.

## Documentation

**Install and use**

- **[QUICKSTART.md](QUICKSTART.md)** — fresh unit → running kiosk: serial bootstrap, then the browser provisioner
- **[FLASHING.md](FLASHING.md)** — the `boota` slot-image model, browser provisioning (enroll → flashos), the on-eMMC layout (A/B slots + stage-2 in `boot1`), recovery
- **[USING.md](USING.md)** — getting into an installed panel, kiosk URL, fleet config

**Build and develop**

- **[BUILDING.md](BUILDING.md)** — host setup (Ubuntu), build pipeline, repo layout, image-size guard
- **[NETBOOT.md](NETBOOT.md)** — TFTP and NFS development path; nothing is written to flash

**Provisioner contracts**

- **[CONFIG-PARTITION.md](CONFIG-PARTITION.md)** — the `cache`-partition blob: autoconfigure key schema + no-serial bootloader updates

## License

GPL-2.0-only (matches the kernel patches it depends on).

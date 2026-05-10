# BUILDING.md

Build a complete TC8 firmware image from a fresh checkout. Two targets share the same kernel, rootfs, and dtbo:

- `emmc` — production, flashed to eMMC slot via fastboot
- `nfs` — netboot bring-up, kernel TFTP'd, rootfs over NFS

## 1. Install prerequisites

On a fresh Ubuntu 22.04+ host:

```bash
sudo apt update
sudo apt install -y \
    git build-essential bison flex bc kmod \
    gcc-aarch64-linux-gnu \
    qemu-user-static binfmt-support \
    debootstrap rsync mtools \
    e2fsprogs python3 openssl libssl-dev
```

`binfmt-support` registers `/proc/sys/fs/binfmt_misc/qemu-aarch64` so `debootstrap --second-stage` can run arm64 binaries inside the chroot. Verify:

```bash
ls /proc/sys/fs/binfmt_misc/qemu-aarch64    # should exist
```

## 2. Clone

```bash
git clone --recurse-submodules https://github.com/Polycom-Open-Firmware/tc8-firmware-build.git
cd tc8-firmware-build
./bootstrap.sh                              # downloads vanilla linux-6.6 into ./linux-6.6
```

## 3. Set the AVB key

You need an RSA-4096 PEM. For development, the AOSP public test key works:

```bash
./scripts/fetch-avb-test-key.sh
export TC8_AVB_KEY=$PWD/testkey_rsa4096.pem
```

The script pulls `external/avb/test/data/testkey_rsa4096.pem` from the AOSP source tree (gitiles, base64-decoded) and verifies it's a valid RSA-4096 PEM. Boots produced with this key pass AVB but show "orange state" on the panel — that's expected for development; the panel's u-boot has Polycom's pubkey burned in, so any non-Polycom-signed boot is "orange".

For production fleets, generate your own:

```bash
openssl genrsa -out my-avb-key.pem 4096
chmod 0600 my-avb-key.pem
export TC8_AVB_KEY=$PWD/my-avb-key.pem
```

…and reflash u-boot's `vbmeta_pubkey` partition (out of scope here).

## 4. (Optional) Bake credentials

Default credentials are **`root` / `root`**, working on tty, USB CDC ACM, and ssh. To change:

```bash
echo 'mySecret' > root_password         # gitignored
# or: export TC8_ROOT_PASSWORD=mySecret
```

To pre-authorize an SSH pubkey for `root`:

```bash
cat ~/.ssh/id_ed25519.pub > authorized_keys     # gitignored
# or: export TC8_SSH_PUBKEY=~/.ssh/id_ed25519.pub
```

The device generates its own SSH host privkey on first boot — host keys are never committed.

## 5. Build

```bash
sudo TC8_AVB_KEY=$TC8_AVB_KEY ./build.sh --profile=emmc
sudo TC8_AVB_KEY=$TC8_AVB_KEY ./build.sh --profile=nfs --skip-rootfs
```

`sudo` is needed for the chroot bind-mounts and `debootstrap`. The first invocation builds rootfs (~10 min) + kernel (~3 min) + AVB-signed boot.img/system.img/dtbo.img/vbmeta.img. The second reuses the rootfs and kernel build cache, only repacking with the netboot cmdline (~30 s).

Outputs:

```
out/emmc/{boot,dtbo,system,vbmeta}.img    out/emmc/SHA256SUMS
out/nfs/{boot,dtbo,system,vbmeta}.img     out/nfs/SHA256SUMS
out/{emmc,nfs}/kernel/Image               (intermediate, used for netboot)
```

## 6. Flash or netboot

- **eMMC**: see [FLASHING.md](FLASHING.md). Connect USB-data, get into fastboot, `fastboot flash boot_b boot.img` etc.
- **Netboot via TFTP+NFS**: see [NETBOOT.md](NETBOOT.md). Drop the kernel + dtb in your TFTP root, extract `rootfs/out/rootfs.tar.gz` to your NFS export, point u-boot at the server.

## 7. Iterate

```bash
./build.sh --profile=emmc --skip-rootfs                 # keep rootfs, rebuild kernel + repack
./build.sh --profile=emmc --skip-kernel --skip-rootfs   # only re-pack from existing artifacts
```

After tweaking `kernel/tc8.config`, the rootfs (the slow part) doesn't have to rebuild.

## Image-size guard

The kernel `Image` must stay under u-boot 2018.03's 32 MiB `BOOTM_LEN` cap on this device:

```bash
ls -lh out/emmc/kernel/Image     # ~24 MiB is fine; >32 MiB will silently fail to boot
```

If the Image grows past the cap, add SoC families to `tc8.config`'s `# CONFIG_ARCH_… is not set` block to drop them.

## What's forced built-in

The rootfs ships **no `/lib/modules/`**, so any driver in this list staying `=m` won't load:

- `DRM=y`, `DRM_KMS_HELPER=y`, `DRM_ETNAVIV=y`, `DRM_PANEL_POLY_LCC=y`
- `DRM_MXSFB=y`, `DRM_IMX_LCDIF=y`, `DRM_SAMSUNG_DSIM=y` — i.MX 8M Mini DSI is the **Samsung DSIM** IP, not NWL
- `PHY_MIXEL_MIPI_DPHY=y` — DSIM's phy supplier
- `BACKLIGHT_CLASS_DEVICE=y`, `BACKLIGHT_PWM=y`, `PWM_IMX27=y`
- `SND_SOC_FSL_SAI=y`, `IMX_SDMA=y`, `SND_SOC_TAS571X=y`
- `NET_DSA_REALTEK_RTL8365MB=y`, `NET_DSA_TAG_RTL8_4=y`
- `USB_LIBCOMPOSITE=y`, `USB_F_ACM=y`, `USB_CONFIGFS=y` — for the USB-data CDC console gadget
- `IP_PNP=y`, `IP_PNP_DHCP=y`, `NFS_FS=y`, `ROOT_NFS=y` — for netboot

If you change the config, verify by reading `/proc/config.gz` on the running device after reflashing — `kconfig` silently demotes `=y` to `=m` if a hard dependency is `=m`.

---

## Appendix — building inside an unprivileged LXC

If you must build inside a Proxmox LXC (instead of a real host), you'll hit problems systemd-tmpfiles can't fix without `CAP_MKNOD`. Two workarounds:

### Recreate `/dev` char devices at boot

systemd-tmpfiles can't `mknod` in unpriv LXCs and silently leaves `/dev/null`, `/dev/zero`, etc. as empty regular files. debootstrap stage 2 and avbtool both fail when that happens. Fix with a oneshot service:

```bash
sudo tee /usr/local/sbin/tc8-fix-devs <<'EOF'
#!/bin/sh
for n in null:1:3 zero:1:5 random:1:8 urandom:1:9 tty:5:0 full:1:7; do
    name=${n%%:*}; mm=${n#*:}; major=${mm%:*}; minor=${mm#*:}
    [ -c /dev/$name ] || { rm -f /dev/$name; mknod -m 666 /dev/$name c $major $minor; }
done
EOF
sudo chmod +x /usr/local/sbin/tc8-fix-devs

sudo tee /etc/systemd/system/tc8-fix-devs.service <<'EOF'
[Unit]
Description=Recreate /dev char devices in unpriv LXC
DefaultDependencies=no
After=local-fs-pre.target
Before=sysinit.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/tc8-fix-devs
RemainAfterExit=yes
[Install]
WantedBy=sysinit.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now tc8-fix-devs.service
```

### `rm -rf rootfs/work` may print "Operation not permitted" warnings

The chroot's `/proc` bind-mount can't be lazily unmounted in an unprivileged LXC, so the cleanup at the end of the rootfs build prints harmless `rm: cannot remove .../proc/<pid>/...` errors. The script tolerates them; the output artifacts are unaffected.

### `sudo` won't show progress streamed to your terminal in some pct-exec setups

If you run the build via `pct exec`, redirect the build to a logfile and `tail -f` it:

```bash
pct exec 200 -- bash -c '
    /usr/local/sbin/tc8-fix-devs
    cd /root/tc8-build
    TC8_AVB_KEY=$TC8_AVB_KEY ./build.sh --profile=emmc 2>&1 | tee /root/build.log
'
```

A native-host build is otherwise straightforward and recommended.

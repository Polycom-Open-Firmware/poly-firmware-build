# Releasing

The release contract: what a tagged release must contain, why the asset
names are load-bearing, and the gates a release passes. Mechanics live in
`.github/workflows/release.yml`; this page is the contract it implements.

## How a release happens

Pushing a tag `v*` runs the release workflow on a GitHub-hosted runner: full
`--target=tc8` build (kiosk profile, chromium baked via `--extra-pkgs`),
kernel-size check, then a GitHub Release with the assets below attached.
The wizard at wizard.openpolycom.cc lists releases live through its proxy —
a new tag appears with no wizard-side work, **provided the asset names
match the contract**.

## TC8 asset contract

TC8 releases are manifest-less: the wizard fabricates the install manifest
client-side from these well-known names. Renaming any of them breaks the
wizard for that release — the names are the API.

| Asset | Role |
|---|---|
| `boot.img` | boota slot image: kernel + ro-root initramfs + cmdline |
| `dtbo.img` | DTB in an Android DTBO container |
| `vbmeta.img` | AVB metadata (`--algorithm NONE`, structurally valid) |
| `rootfs.simg` | sparse rootfs → `userdata`; the default (kiosk) profile |
| `tc8-stage2-uboot.bin` | stage-2 U-Boot for eMMC boot1 (enroll + field update) |
| `tc8-gpt-restore.simg` | partition-table repair image (see `gpt-restore/README.md`) |
| `version.env` | build metadata (sourceable; `TC8_FW_VERSION`, `TC8_OS_PROFILES`, …) |
| `SHA256SUMS` | checksums over the image set |

The build can emit per-profile `rootfs-<profile>.simg` variants (`--os-profile=`);
releases currently ship only the default-profile `rootfs.simg`.

The fabricated manifests the wizard derives from these:
`manifest.json` → `{ "stage2": { "url": "tc8-stage2-uboot.bin" } }`;
`os-manifest.json` → `boot`/`dtbo`/`vbmeta`/`rootfs` keyed to the four
image names above.

## C60 asset contract

C60 releases are manifest-driven: the release carries a real
`c60-manifest.json` (SDP `bootSeq` addresses are build-specific, so it must
come from the build, not be fabricated). Its `os` section — when present —
lists the OS image set; without it the wizard offers unlock only. The
schema is owned by the wizard side: `provisioner/C60.md`.

## Gates

- **Kernel size:** `Image` must stay under 32 MiB (stock U-Boot `BOOTM_LEN`);
  the workflow fails the release past it.
- **C60 hardware gate:** C60 artifacts from this tree require boot
  verification on hardware before they ship in a release.
- **Checksums:** the workflow writes `SHA256SUMS` over the shipped set; a
  consumer verifies the download with `sha256sum -c`.

## Consumers

- The wizard (release list + assets via the Cloudflare proxy; asset names
  above are its lookup keys).
- `provisioner/CLOUDFLARE.md` — how assets stream to the browser.
- The apt archive is versioned independently — images resolve packages
  against archive HEAD at build time; a release snapshots by virtue of the
  image (see the `apt` repo's `PUBLISHING.md`).

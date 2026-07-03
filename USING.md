# Using the panel

Getting into an installed panel and changing its configuration.

## Getting in

The image bakes several ways in:

- **Composite USB gadget** on the micro-B data port — three interfaces:
  - **CDC ACM** → `/dev/ttyACM0` on Linux, "USB Serial Device" on Windows.
    systemd-getty spawns a login prompt automatically.
  - **CDC NCM** → `usb0` USB-Ethernet on the host. Panel runs DHCP on
    `10.55.0.1/24` and leases the host `.2`–`.5`. ssh to `10.55.0.1` the
    moment the link comes up.
  - **MTP / Portable Device** — `/data` exposed by uMTP-Responder.
    Drag-and-drop in any native file manager.
- **ssh** on the wired LAN (port 22).

Default credentials: **`root` / `root`**. Change them before plugging the
panel into anything you care about:

```sh
passwd                                             # change the root password
mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys   # paste your pubkey, Ctrl-D
```

To bake different credentials into the image at build time, see
[BUILDING.md](BUILDING.md).

## Configuring the kiosk URL

The kiosk reads `/etc/default/tc8-kiosk`:

```sh
KIOSK_URL=https://your-page.example.com/
COG_OPTS=--enable-media=true
```

After editing, `systemctl restart kiosk`.

## Fleet configuration (no shell)

Hostname, kiosk URL, credentials, NTP, timezone, CA certs and more can be
pushed over fastboot by the provisioner — a config blob flashed to the
`cache` partition, applied on every boot. See
[CONFIG-PARTITION.md](CONFIG-PARTITION.md) for the key schema.

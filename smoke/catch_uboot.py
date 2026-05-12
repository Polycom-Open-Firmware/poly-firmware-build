#!/usr/bin/env python3
"""catch_uboot.py — drive a TC8 panel into u-boot via the brainslug UART.

Uses /uart/1/ws (full-duplex WebSocket) so one TCP connection carries both
the ^C spam (client → slug) and the panel UART output (slug → client). HTTP
POST per Ctrl-C used to cap us at ~67 bursts/s; over WS we're UART-baud
limited (>1k bursts/s) and reliably catch u-boot inside the bootdelay window.

Stdlib only — no `pip install websockets` needed on the runner.

Usage:
  catch_uboot.py --brainslug http://10.99.0.35
"""
import argparse, base64, os, re, select, socket, struct, sys, time
from urllib.parse import urlparse


def ws_connect(url, path, timeout=5):
    """Minimal RFC 6455 client. Returns (sock,) ready for masked send / unmasked recv."""
    u = urlparse(url)
    host, port = u.hostname, u.port or 80
    s = socket.create_connection((host, port), timeout=timeout)
    s.settimeout(timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    s.sendall(req.encode())
    # Read response headers.
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise RuntimeError("ws handshake: connection closed mid-response")
        buf += chunk
    head, _, leftover = buf.partition(b"\r\n\r\n")
    if b"101" not in head.split(b"\r\n")[0]:
        raise RuntimeError(f"ws handshake: {head.split(chr(13).encode())[0]!r}")
    s.setblocking(False)
    return s, leftover  # any bytes after the headers are part of the WS stream


def ws_send_binary(sock, payload):
    """Send a single masked binary frame. Payload < 64 KiB for our use."""
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    n = len(payload)
    if n < 126:
        header = struct.pack("!BB", 0x82, 0x80 | n) + mask
    elif n < 65536:
        header = struct.pack("!BBH", 0x82, 0x80 | 126, n) + mask
    else:
        header = struct.pack("!BBQ", 0x82, 0x80 | 127, n) + mask
    sock.sendall(header + masked)


def ws_recv_all_available(sock, leftover, max_bytes=65536):
    """Pull frames until the socket would block. Returns (payload_bytes, new_leftover).
    Handles fragmented frames sloppily — we only care about payload data."""
    out = bytearray()
    buf = bytearray(leftover)

    def need(n):
        while len(buf) < n:
            try:
                chunk = sock.recv(8192)
            except (BlockingIOError, socket.timeout):
                return False
            if not chunk:
                return False
            buf.extend(chunk)
        return True

    while True:
        # Pull whatever is queued without blocking.
        try:
            chunk = sock.recv(8192)
            if chunk:
                buf.extend(chunk)
            elif not buf:
                break
        except (BlockingIOError, socket.timeout):
            if not buf:
                break

        if len(buf) < 2:
            break
        b1, b2 = buf[0], buf[1]
        plen = b2 & 0x7F
        idx = 2
        if plen == 126:
            if not need(4): break
            plen = struct.unpack("!H", bytes(buf[2:4]))[0]; idx = 4
        elif plen == 127:
            if not need(10): break
            plen = struct.unpack("!Q", bytes(buf[2:10]))[0]; idx = 10
        masked = bool(b2 & 0x80)
        if masked:
            if not need(idx + 4): break
            mask = bytes(buf[idx:idx+4]); idx += 4
        if not need(idx + plen): break
        payload = bytes(buf[idx:idx+plen])
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        opcode = b1 & 0x0F
        if opcode in (0x1, 0x2, 0x0):   # text/binary/continuation
            out.extend(payload)
        elif opcode == 0x8:             # close
            return bytes(out), b""
        # opcode 0x9 ping / 0xA pong — ignore; httpd handles control frames
        buf = buf[idx+plen:]
        if len(out) >= max_bytes:
            break
    return bytes(out), bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--brainslug', required=True, help='http://host[:port]')
    ap.add_argument('--port', type=int, default=1)
    ap.add_argument('--total-timeout', type=float, default=90,
                    help='wallclock seconds before giving up')
    args = ap.parse_args()

    path = f"/uart/{args.port}/ws"
    sock, leftover = ws_connect(args.brainslug, path)
    print(f"[+] ws connected: {args.brainslug}{path}", flush=True)

    burst = b'\x03 \r' * 8
    prompt_re = re.compile(rb'(u-boot=> |^=> )')
    rx_buf = bytearray()
    sends = 0
    start = time.monotonic()
    deadline = start + args.total_timeout

    # Pace sends so we don't outrun the slug's httpd work queue. ~200/s is
    # comfortably above the bootdelay polling rate but well under what fills
    # the TCP recv buffer faster than the slug drains it. (At 24 B/burst this
    # is also far below the 115200-baud UART ceiling.)
    send_interval = 1.0 / 50
    next_send = time.monotonic()

    while time.monotonic() < deadline:
        # Drain RX first — keeps the slug's send side flowing and lets us
        # detect the prompt the instant it arrives.
        readable, _, _ = select.select([sock], [], [], 0)
        if readable:
            data, leftover = ws_recv_all_available(sock, leftover)
            if data:
                rx_buf.extend(data)
                if len(rx_buf) > 16384:
                    del rx_buf[:len(rx_buf) - 8192]
                # Search just the tail (anchored to end of buffer).
                if prompt_re.search(rx_buf[-200:]):
                    elapsed = time.monotonic() - start
                    print(f"[+] u-boot prompt caught after {sends} bursts "
                          f"({elapsed:.1f}s)", flush=True)
                    time.sleep(0.2)
                    sys.exit(0)

        now = time.monotonic()
        if now >= next_send:
            try:
                ws_send_binary(sock, burst)
                sends += 1
                next_send = now + send_interval
            except BlockingIOError:
                # Slug-side TCP recv buffer is momentarily full; back off briefly.
                time.sleep(0.005)
            except OSError as e:
                print(f"[!] send error: {e}", flush=True)
                break
        else:
            # Small sleep so we don't spin between sends.
            time.sleep(min(0.002, next_send - now))

    elapsed = time.monotonic() - start
    print(f"[!] gave up after {sends} bursts ({elapsed:.1f}s); "
          f"tail: {bytes(rx_buf[-200:])!r}", file=sys.stderr, flush=True)
    sys.exit(1)


if __name__ == '__main__':
    main()

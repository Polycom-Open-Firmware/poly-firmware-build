#!/usr/bin/env python3
"""catch_uboot.py — drive a TC8 panel into u-boot via the brainslug UART.

Usage:
  catch_uboot.py --brainslug http://10.99.0.35

Reads continuously from /uart/<port>/read (default port 1). When the
"Hit any key to stop autoboot" banner appears, slams Ctrl-C for ~3s and
then sends a CR to confirm we're at the `u-boot=> ` prompt. Exits 0 if
caught, non-zero otherwise. Leaves the panel at the prompt — caller
follows up with whatever u-boot commands they want.

If a slug HTTP read loop runs at ~20 polls/sec (50ms), the slug's 8 KiB
RX ring won't overflow on this UART (115200 baud => ~12 KB/sec).
"""
import argparse, sys, time, urllib.request, urllib.error

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--brainslug', required=True, help='http://host')
    ap.add_argument('--port', type=int, default=1)
    ap.add_argument('--total-timeout', type=int, default=180,
                    help='seconds to spend waiting for a prompt')
    ap.add_argument('--spam-seconds', type=float, default=4.0,
                    help='how long to slam Ctrl-C after the banner')
    args = ap.parse_args()

    base = f"{args.brainslug.rstrip('/')}/uart/{args.port}"

    def w(b):
        req = urllib.request.Request(base+'/write', data=b, method='POST',
                                     headers={'Content-Type': 'application/octet-stream'})
        try: urllib.request.urlopen(req, timeout=3).read()
        except Exception: pass

    def r():
        try:
            return urllib.request.urlopen(base+'/read', timeout=3).read()
        except Exception:
            return b''

    buf = b''
    end = time.monotonic() + args.total_timeout
    print('[+] watching for autoboot banner', flush=True)
    while time.monotonic() < end:
        chunk = r()
        if chunk:
            buf += chunk
            if len(buf) > 32768:
                buf = buf[-16384:]
            if b'Hit any key to stop autoboot' in buf:
                print('[+] banner seen — spamming ^C', flush=True)
                break
        time.sleep(0.05)
    else:
        # No banner — fall through; bootdelay=0 panels never print one
        print('[+] no banner in window; trying spam-anyway path', flush=True)

    spam_end = time.monotonic() + args.spam_seconds
    burst = b'\x03 \r' * 8
    while time.monotonic() < spam_end:
        w(burst)
        time.sleep(0.02)

    # Settle: drain, send CR, see prompt.
    time.sleep(0.3)
    r()
    w(b'\r')
    time.sleep(0.6)
    tail = r()
    if b'u-boot=> ' in tail or b'=>' in tail[-50:]:
        print('[+] u-boot prompt caught', flush=True)
        sys.exit(0)

    # One more retry: panel might still be coming up; spam again.
    print('[!] no prompt after first attempt; retrying', flush=True)
    spam_end = time.monotonic() + 3
    while time.monotonic() < spam_end:
        w(burst); time.sleep(0.02)
    time.sleep(0.5); r()
    w(b'\r'); time.sleep(0.7)
    tail = r()
    if b'u-boot=> ' in tail or b'=>' in tail[-50:]:
        print('[+] u-boot prompt caught (retry)', flush=True)
        sys.exit(0)

    sys.stderr.write('ERROR: never caught u-boot prompt\n')
    sys.stderr.write(f'    last tail: {tail[-200:]!r}\n')
    sys.exit(1)

if __name__ == '__main__':
    main()

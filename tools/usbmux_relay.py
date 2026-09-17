#!/usr/bin/env python3
"""Minimal usbmux TCP relay: listen locally, forward to device port via /var/run/usbmuxd."""
import plistlib, socket, struct, sys, threading

USBMUXD_SOCK = "/var/run/usbmuxd"

def mux_connect(device_id, port):
    # PortNumber must be byte-swapped (network order) per usbmux protocol
    payload = {
        "MessageType": "Connect",
        "DeviceID": device_id,
        "PortNumber": socket.htons(port),
        "ProgName": "usbmux_relay",
    }
    body = plistlib.dumps(payload, fmt=plistlib.FMT_XML)
    hdr = struct.pack("<IIII", 16 + len(body), 1, 8, 1)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(USBMUXD_SOCK)
    s.sendall(hdr + body)
    # read response header + plist
    rh = s.recv(16)
    if len(rh) < 16:
        raise RuntimeError("short usbmux reply")
    mlen, ver, mtype, tag = struct.unpack("<IIII", rh)
    plen = mlen - 16
    data = b""
    while len(data) < plen:
        chunk = s.recv(plen - len(data))
        if not chunk:
            break
        data += chunk
    resp = plistlib.loads(data)
    if resp.get("Number", 0) != 0:
        raise RuntimeError("usbmux Connect failed: %r" % resp)
    return s

def first_device():
    payload = {"MessageType": "ListDevices", "ProgName": "usbmux_relay", "ClientVersionString": "1"}
    body = plistlib.dumps(payload, fmt=plistlib.FMT_XML)
    hdr = struct.pack("<IIII", 16 + len(body), 1, 8, 1)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(USBMUXD_SOCK)
    s.sendall(hdr + body)
    rh = s.recv(16)
    mlen, ver, mtype, tag = struct.unpack("<IIII", rh)
    plen = mlen - 16
    data = b""
    while len(data) < plen:
        chunk = s.recv(plen - len(data))
        if not chunk:
            break
        data += chunk
    s.close()
    resp = plistlib.loads(data)
    devs = resp.get("DeviceList", [])
    if not devs:
        raise RuntimeError("no devices")
    return devs[0]["DeviceID"]

def pump(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    finally:
        for x in (a, b):
            try:
                x.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

def main():
    lport = int(sys.argv[1]) if len(sys.argv) > 1 else 2222
    dport = int(sys.argv[2]) if len(sys.argv) > 2 else 44
    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", lport))
    ls.listen(5)
    print("listening on 127.0.0.1:%d -> device:%d" % (lport, dport), flush=True)
    while True:
        c, _ = ls.accept()
        try:
            dev = first_device()
            m = mux_connect(dev, dport)
        except Exception as e:
            print("mux connect failed:", e, flush=True)
            c.close()
            continue
        threading.Thread(target=pump, args=(c, m), daemon=True).start()
        threading.Thread(target=pump, args=(m, c), daemon=True).start()

if __name__ == "__main__":
    main()

"""Saves a screenshot of the desktop through noVNC, run inside the desktop
image by smoke.sh: a second, headless browser opens noVNC's page, waits
for it to connect to the screen, then takes the shot over CDP.

usage: python3 - OUT.png < screenshot.py
"""

import base64
import http.client
import json
import os
import socket
import struct
import subprocess
import sys
import time
import urllib.parse

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/desktop.png"
PORT = 9333
URL = "http://127.0.0.1:6080/vnc.html?autoconnect=true&resize=scale"


def devtools(method, path):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=10)
    c.request(method, path)
    return json.loads(c.getresponse().read())


class WS:
    def __init__(self, url):
        u = urllib.parse.urlsplit(url)
        self.s = socket.create_connection((u.hostname, u.port), 30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(
            f"GET {u.path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n".encode()
        )
        head = b""
        while b"\r\n\r\n" not in head:
            head += self.s.recv(1)
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise RuntimeError(head.decode(errors="replace"))
        self.n = 0

    def exact(self, n):
        b = b""
        while len(b) < n:
            chunk = self.s.recv(n - len(b))
            if not chunk:
                raise EOFError
            b += chunk
        return b

    def call(self, method, **params):
        self.n += 1
        data = json.dumps({"id": self.n, "method": method, "params": params}).encode()
        mask = os.urandom(4)
        n = len(data)
        head = struct.pack(">BB", 0x81, 0x80 | n) if n < 126 else struct.pack(">BBH", 0x81, 0x80 | 126, n)
        self.s.sendall(head + mask + bytes(b ^ mask[i & 3] for i, b in enumerate(data)))
        while True:
            msg = b""
            while True:
                b0, b1 = self.exact(2)
                n = b1 & 0x7F
                if n == 126:
                    (n,) = struct.unpack(">H", self.exact(2))
                elif n == 127:
                    (n,) = struct.unpack(">Q", self.exact(8))
                msg += self.exact(n)
                if b0 & 0x80:
                    break
            reply = json.loads(msg)
            if reply.get("id") == self.n:
                return reply.get("result", reply)


browser = subprocess.Popen(
    ["browser", "--headless=new", "--user-data-dir=/tmp/screenshot", f"--remote-debugging-port={PORT}",
     "--window-size=1280,860", "--hide-scrollbars", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
try:
    t = time.monotonic()
    while True:
        try:
            devtools("GET", "/json/version")
            break
        except OSError:
            if time.monotonic() - t > 30:
                sys.exit("the headless browser didn't start")
            time.sleep(0.2)
    target = devtools("PUT", "/json/new?" + urllib.parse.quote(URL, safe=""))
    ws = WS(target["webSocketDebuggerUrl"])
    # noVNC connects, then the first frames arrive.
    time.sleep(8)
    shot = ws.call("Page.captureScreenshot", format="png")
    with open(OUT, "wb") as f:
        f.write(base64.b64decode(shot["data"]))
    print(OUT)
finally:
    browser.kill()

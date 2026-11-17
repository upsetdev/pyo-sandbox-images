#!/usr/bin/env bash
# Checks an image the way Pyo uses it.
#
#   scripts/smoke.sh base IMAGE
#   scripts/smoke.sh desktop IMAGE [SCREENSHOT.png]
#
# Commands run as pyo-envd runs them: as root in /root, with only HOME,
# LANG, TERM and PATH set, not the image's own Env.
# `desktop` starts /etc/pyo/start in a container, then checks voxl's page
# (and where noVNC's was, with the sandbox's name), Pyo's changes to it
# and its icons, its WebSocket, its screenshot, CDP, the browser and the
# dock on 127.0.0.1 inside it, and the third-party notices. With a path
# it also saves a screenshot of voxl's page as a viewer sees it, taken by
# a second, headless browser in the image.
set -euo pipefail

kind=${1:?usage: smoke.sh base|desktop IMAGE [SCREENSHOT.png]}
image=${2:?usage: smoke.sh base|desktop IMAGE [SCREENSHOT.png]}
shot=${3:-}
ENVD=(env -i HOME=/root LANG=C.UTF-8 TERM=xterm-256color
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin)

fails=0
ok() { printf '  ok    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }

# The contract every image keeps (README.md, contract 1).
contract() {
  local label user
  label=$(docker image inspect -f '{{index .Config.Labels "dev.pyo.sandbox.contract"}}' "$image")
  [ "$label" = 1 ] && ok "label dev.pyo.sandbox.contract=1" || bad "label dev.pyo.sandbox.contract is '$label'"
  user=$(docker image inspect -f '{{.Config.User}}' "$image")
  [ -z "$user" ] || [ "$user" = root ] && ok "runs as root" || bad "image user is $user"
}

# Every tool, with its version, the way envd runs commands.
tools() {
  echo "Tools in $image"
  docker run --rm --workdir /root "$image" "${ENVD[@]}" bash -c '
    fails=0
    v() { local name=$1; shift
      if all=$("$@" 2>&1); then printf "  ok    %-14s %s\n" "$name" "$(echo "$all" | grep -m1 .)"
      else printf "  FAIL  %-14s %s\n" "$name" "$(echo "$all" | grep -m1 .)"; fails=$((fails + 1)); fi; }
    [ "$(id -u)" = 0 ] && [ "$PWD" = /root ] || { echo "  FAIL  not root in /root"; fails=$((fails + 1)); }
    for d in /proc /sys /dev /tmp /run /mnt /root; do [ -d $d ] || { echo "  FAIL  no $d"; fails=$((fails + 1)); }; done
    v os           sh -c ". /etc/os-release; echo \$PRETTY_NAME"
    v arch         uname -m
    v git          git --version
    v gh           gh --version
    v curl         curl --version
    v wget         wget --version
    v jq           jq --version
    v rg           rg --version
    v zip          sh -c "zip -v | grep -m1 \"This is Zip\""
    v unzip        unzip -v
    v xz           xz --version
    v less         less --version
    v vim          vim --version
    v nano         nano --version
    v ssh          ssh -V
    v rsync        rsync --version
    v ps           ps --version
    v ip           ip -V
    v ping         ping -V
    v dig          dig -v
    v sudo         sudo --version
    v locale       sh -c "locale -a | grep -ix en_US.utf8"
    v tzdata       sh -c "test -f /usr/share/zoneinfo/UTC && echo /usr/share/zoneinfo/UTC"
    v gcc          gcc --version
    v make         make --version
    v pkg-config   pkg-config --version
    v cmake        cmake --version
    v ninja        ninja --version
    v python3      python3 --version
    v python       python --version
    v pip          pip --version
    v venv         sh -c "python3 -m venv /tmp/venv && /tmp/venv/bin/python -c \"print(\\\"venv ok\\\")\""
    v uv           uv --version
    v uvx          uvx --version
    v node         node --version
    v npm          npm --version
    v corepack     corepack --version
    v pnpm         pnpm --version
    v bun          bun --version
    v deno         deno --version
    v docker       docker --version
    v buildx       docker buildx version
    v compose      docker compose version
    v claude       claude --version
    v codex        sh -c "codex --version 2>/dev/null"
    v opencode     opencode --version
    if [ -x /usr/local/bin/browser ]; then
      v browser    browser --version
      v google-chrome google-chrome --version
      v chromium   chromium --version
      v Xvfb       dpkg-query -W xvfb
      v voxl       voxl --version
      v openbox    openbox --version
      v pyo-dock   sh -c "test -x /usr/local/bin/pyo-dock && ! ldd /usr/local/bin/pyo-dock | grep -q \"not found\" && echo /usr/local/bin/pyo-dock"
      v wmctrl     wmctrl --version
      v xdotool    xdotool --version
      v xfce4-terminal dpkg-query -W xfce4-terminal
      v pcmanfm    dpkg-query -W pcmanfm
      v xwallpaper dpkg-query -W xwallpaper
      v fonts      sh -c "fc-list | grep -c -iE \"dejavu|liberation|emoji|droid\""
      v inter      sh -c "fc-list | grep -m1 -i \"Inter Variable\""
      v jetbrains  sh -c "fc-list | grep -m1 -i \"JetBrains Mono\""
      cat /etc/pyo/browser | sed "s/^/        /"
    fi
    exit $fails
  ' || fails=$((fails + $?))
}

desktop() {
  echo "Desktop in $image"
  local name="pyo-smoke-$$"
  docker run -d --name "$name" --init --shm-size=1g "$image" "${ENVD[@]}" /etc/pyo/start >/dev/null
  trap "docker rm -f $name >/dev/null 2>&1 || true" EXIT
  docker exec -i "$name" "${ENVD[@]}" python3 - <<'PY' || fails=$((fails + $?))
import base64, http.client, json, os, socket, subprocess, time

fails = 0
def ok(m): print(f"  ok    {m}")
def bad(m):
    global fails
    fails += 1
    print(f"  FAIL  {m}")

# The listener is up at once. Nothing else runs yet.
t = time.monotonic()
while True:
    try:
        socket.create_connection(("127.0.0.1", 6080), 1).close()
        break
    except OSError:
        if time.monotonic() - t > 10:
            bad("nothing listens on 6080"); raise SystemExit(fails)
        time.sleep(0.1)
ok(f"listener on 6080 in {int((time.monotonic() - t) * 1000)}ms")
ps = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True).stdout.split()
idle = not any(p in ps for p in ("Xvfb", "voxl", "chrome", "chromium"))
ok("nothing else runs before first use") if idle else bad(f"started early: {ps}")

def request(path, headers=None, port=6080):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=90)
    c.request("GET", path, headers=headers or {})
    r = c.getresponse()
    return r.status, dict((k.lower(), v) for k, v in r.getheaders()), r.read()

# Where Pyo opens the desktop (noVNC's page) goes on to voxl's, with the
# cookie that lets its WebSocket in.
s, h, _ = request("/vnc.html?autoconnect=1&resize=remote&reconnect=1")
cookie = h.get("set-cookie", "").split(";")[0]
if s == 303 and h.get("location") == "./" and cookie.startswith("pyo_desktop="):
    ok("vnc.html goes on to ./ with its cookie")
else:
    bad(f"vnc.html: {s} {h}")
# The sandbox's name goes on to the page, for its title.
s, h, _ = request("/vnc.html?autoconnect=1&name=my%20box%0A&app=x")
if s == 303 and h.get("location") == "./?name=my%20box":
    ok("vnc.html?name= goes on to ./?name=")
else:
    bad(f"vnc.html?name=: {s} {h.get('location')}")
s, h, body = request("/")
ok(f"voxl's page {s}, {len(body)} bytes") if s == 200 and b"client.js" in body else bad(f"voxl's page: {s} {body[:200]!r}")
ok("its cookie with it") if h.get("set-cookie", "").startswith("pyo_desktop=") else bad(f"no cookie with the page: {h}")
# Pyo's changes to the page (images/desktop/voxl/patches): its icons, its
# loading screen and voxl's notice.
if b'href="favicon.svg"' in body and b'id="status-text"' in body and b"Copyright (c) 2026 Tembo" in body:
    ok("the page has Pyo's icons, loading screen and voxl's notice")
else:
    bad("the page lacks Pyo's changes")
for f in ("client.js", "worker.js"):
    s, _, body = request("/" + f)
    ok(f"{f} {s}, {len(body)} bytes") if s == 200 and len(body) > 1000 else bad(f"{f} {s}")
    ok(f"{f} has voxl's notice") if b"Copyright (c) 2026 Tembo" in body else bad(f"{f} has no notice")
_, _, body = request("/client.js")
ok("the title takes the name") if b" | " in body and b"name" in body else bad("client.js doesn't set the title")
for f, kind, magic in (("favicon.svg", "image/svg+xml", b"<svg"), ("favicon.ico", "image/x-icon", b"\0\0\1\0")):
    s, h, body = request("/" + f)
    if s == 200 and h.get("content-type") == kind and body.startswith(magic):
        ok(f"{f} {s}, {len(body)} bytes")
    else:
        bad(f"{f}: {s} {h.get('content-type')}")

# voxl's WebSocket: 101, then its hello (JSON), as from voxl's page through Pyo
# (another origin, with the cookie). Without the cookie, a page of another
# site is turned away, and so is a Host that isn't localhost.
def websocket(headers):
    sock = socket.create_connection(("127.0.0.1", 6080), 30)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((
        "GET /ws HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
        + "".join(f"{k}: {v}\r\n" for k, v in headers.items()) + "\r\n").encode())
    sock.settimeout(30)
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    status = data.split(b"\r\n", 1)[0].decode(errors="replace")
    rest = data.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in data else b""
    if " 101 " in status:
        while len(rest) < 4:
            chunk = sock.recv(4096)
            if not chunk:
                break
            rest += chunk
        n = rest[1] & 0x7F
        start = 2 if n < 126 else 4 if n == 126 else 10
        while len(rest) < start + 64:
            chunk = sock.recv(4096)
            if not chunk:
                break
            rest += chunk
        rest = rest[start:]
    sock.close()
    return status, rest

status, first = websocket({"Host": "localhost:6080", "Origin": "http://100.64.0.2:7070", "Cookie": cookie})
if " 101 " in status and first.startswith(b'{"'):
    ok(f"websocket: {status}, then voxl's hello {first[:24].decode(errors='replace')}…")
else:
    bad(f"websocket: {status} {first[:40]!r}")
status, _ = websocket({"Host": "localhost:6080", "Origin": "https://another-site.example"})
ok("another site's page is turned away") if " 403 " in status else bad(f"another site's page: {status}")
status, _ = websocket({"Host": "rebound.example:6080", "Origin": "http://rebound.example:6080", "Cookie": cookie})
ok("a Host that isn't localhost is turned away") if " 403 " in status else bad(f"another Host: {status}")
s, _, _ = request("/screenshot", port=6901)
ok(f"voxl itself needs its password ({s})") if s == 401 else bad(f"voxl answered without its password: {s}")

# The desktop on the screen, as voxl sees it: not black, and the dock's
# color at the bottom.
def png_pixels(data):
    import struct, zlib
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    i, idat = 8, b""
    while i < len(data):
        n, kind = struct.unpack(">I4s", data[i:i + 8])
        chunk = data[i + 8:i + 8 + n]
        if kind == b"IHDR":
            w, h, depth, color = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        i += 12 + n
    bpp = {2: 3, 6: 4}[color]
    raw, rows, prev = zlib.decompress(idat), [], bytearray(w * bpp)
    stride = w * bpp
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line)); prev = line
    return w, h, bpp, rows

time.sleep(2)
s, h, png = request("/screenshot")
try:
    w, hh, bpp, rows = png_pixels(png)
    lit = sum(1 for row in rows[::8] for x in range(0, w * bpp, bpp * 8) if sum(row[x:x + 3]) > 60)
    total = len(rows[::8]) * len(range(0, w * bpp, bpp * 8))
    if s == 200 and lit > total * 0.9:
        ok(f"screenshot {w}x{hh}, {100 * lit // total}% not black")
    else:
        bad(f"screenshot {s}: {100 * lit // max(total, 1)}% not black")
    open("/tmp/voxl-screenshot.png", "wb").write(png)
except Exception as e:
    bad(f"screenshot {s}: {e}")
s, _, body = request("/wait?idle=200&timeout=5000")
ok(f"/wait {s}: {body.decode(errors='replace').strip()}") if s == 200 and b"changed" in body else bad(f"/wait {s} {body[:80]!r}")

# The browser's managed policies, where Chrome and Chromium read them.
for d in ("/etc/opt/chrome", "/etc/chromium"):
    try:
        p = json.load(open(f"{d}/policies/managed/pyo.json"))
        ok(f"{d} policies, BrowserSignin {p['BrowserSignin']}") if p.get("BrowserSignin") == 0 else bad(f"{d} policies: {p}")
    except Exception as e:
        bad(f"{d} policies: {e}")

# CDP on 9222, and the browser behind it.
t = time.monotonic()
try:
    s, _, body = request("/json/version", port=9222)
    v = json.loads(body)
    ok(f"CDP /json/version {s} in {time.monotonic() - t:.1f}s: {v.get('Browser')}")
except Exception as e:
    bad(f"CDP /json/version: {e}")

# vnc.html?app=chromium (Pyo's Open browser) brings the browser to the front.
request("/vnc.html?app=chromium")
env = dict(os.environ, DISPLAY=":1")
t = time.monotonic()
while time.monotonic() - t < 20:
    out = subprocess.run(["wmctrl", "-lx"], env=env, capture_output=True, text=True).stdout
    if "chrom" in out.lower():
        break
    time.sleep(0.5)
ok("?app=chromium: the browser has a window") if "chrom" in out.lower() else bad(f"?app=chromium: no browser window: {out!r}")
ok("the dock (pyo-dock) is up") if "pyo-dock" in out.lower() else bad(f"no dock: {out!r}")
s = subprocess.run(["xdotool", "search", "--onlyvisible", "--class", "chrom", "getwindowgeometry"],
                   env=env, capture_output=True, text=True).stdout
ok("the browser is maximized") if "1280x" in s else bad(f"the browser isn't maximized: {s!r}")

# Third-party notices.
for f in ("/usr/share/doc/pyo-sandbox-images/THIRD_PARTY_NOTICES.md", "/usr/share/doc/voxl/LICENSE",
          "/usr/share/doc/voxl/copyright", "/usr/share/doc/voxl/SOURCE", "/usr/share/doc/voxl/crates/README.md",
          "/usr/share/doc/voxl/patches/0001-pyo-web-page.patch", "/usr/share/doc/libx264-164/copyright"):
    ok(f"{f}") if os.path.getsize(f) > 0 else bad(f"{f} is empty")

log = open("/var/log/pyo-desktop.log").read()
ok(f"/var/log/pyo-desktop.log, {len(log.splitlines())} lines") if "listening on 6080" in log else bad("no /var/log/pyo-desktop.log")
raise SystemExit(fails)
PY
  if [ -n "$shot" ]; then
    # voxl's page in a second, headless browser, as a viewer sees it.
    mkdir -p "$(dirname "$shot")"
    if timeout 90 docker exec -i "$name" "${ENVD[@]}" python3 - /tmp/desktop.png \
        < "$(dirname "$0")/screenshot.py" >/dev/null &&
      docker cp "$name:/tmp/desktop.png" "$shot" >/dev/null; then
      ok "screenshot: $shot"
    else
      bad "no screenshot"
    fi
  fi
  if [ "$fails" -gt 0 ]; then
    echo "  /var/log/pyo-desktop.log:"
    docker exec "$name" cat /var/log/pyo-desktop.log | sed 's/^/    /' || true
  fi
}

case "$kind" in
  base) contract; tools ;;
  desktop) contract; tools; desktop ;;
  *) echo "usage: smoke.sh base|desktop IMAGE [SCREENSHOT.png]" >&2; exit 2 ;;
esac

if [ "$fails" -gt 0 ]; then
  echo "$fails check(s) failed"
  exit 1
fi
echo "All checks passed"

#!/usr/bin/env bash
# Checks an image the way Pyo uses it.
#
#   scripts/smoke.sh base IMAGE
#   scripts/smoke.sh desktop IMAGE [SCREENSHOT.png]
#
# Commands run as pyo-envd runs them: as root in /root, with only HOME,
# LANG, TERM and PATH set, not the image's own Env.
# `desktop` starts /etc/pyo/start in a container, then checks noVNC, its
# WebSocket and CDP on 127.0.0.1 inside it. With a path it also saves a
# screenshot of the desktop through noVNC, taken by the image's browser.
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
      v Xvnc       sh -c "Xvnc -version 2>&1 | grep -m1 TigerVNC"
      v openbox    openbox --version
      v tint2      sh -c "tint2 -v 2>&1 | grep -m1 -i \"tint2 version\""
      v wmctrl     wmctrl --version
      v xdotool    xdotool --version
      v xfce4-terminal dpkg-query -W xfce4-terminal
      v fonts      sh -c "fc-list | grep -c -iE \"dejavu|liberation|emoji|droid\""
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

def get(port, path, timeout=90):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    c.request("GET", path)
    r = c.getresponse()
    return r.status, r.read()

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
idle = not any(p in ps for p in ("Xvnc", "chrome", "chromium"))
ok("nothing else runs before first use") if idle else bad(f"started early: {ps}")

s, body = get(6080, "/vnc.html")
ok(f"vnc.html {s}, {len(body)} bytes") if s == 200 and b"noVNC" in body else bad(f"vnc.html {s}")
s, _ = get(6080, "/app/ui.js")
ok(f"app/ui.js {s}") if s == 200 else bad(f"app/ui.js {s}")

# noVNC's WebSocket: 101, then the screen's VNC greets in a binary frame.
sock = socket.create_connection(("127.0.0.1", 6080), 30)
key = base64.b64encode(os.urandom(16)).decode()
sock.sendall((
    "GET /websockify HTTP/1.1\r\nHost: 127.0.0.1:6080\r\nUpgrade: websocket\r\n"
    f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
    "Sec-WebSocket-Protocol: binary\r\n\r\n").encode())
sock.settimeout(30)
data = b""
while b"\r\n\r\n" not in data:
    chunk = sock.recv(4096)
    if not chunk:
        break
    data += chunk
status = data.split(b"\r\n", 1)[0].decode(errors="replace")
ok(f"websocket: {status}") if " 101 " in status else bad(f"websocket: {status}")
rest = data.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in data else b""
while len(rest) < 14:
    chunk = sock.recv(4096)
    if not chunk:
        break
    rest += chunk
greeting = rest[2:14]
ok(f"VNC through it: {greeting.decode().strip()}") if greeting.startswith(b"RFB ") else bad(f"no VNC greeting: {rest[:20]!r}")
sock.close()

# The browser's managed policies, where Chrome and Chromium read them.
for d in ("/etc/opt/chrome", "/etc/chromium"):
    try:
        p = json.load(open(f"{d}/policies/managed/pyo.json"))
        ok(f"{d} policies, BrowserSignin {p['BrowserSignin']}") if p.get("BrowserSignin") == 0 else bad(f"{d} policies: {p}")
    except Exception as e:
        bad(f"{d} policies: {e}")

# CDP on 9222 starts the browser when it isn't running.
t = time.monotonic()
try:
    s, body = get(9222, "/json/version")
    v = json.loads(body)
    ok(f"CDP /json/version {s} in {time.monotonic() - t:.1f}s: {v.get('Browser')}")
except Exception as e:
    bad(f"CDP /json/version: {e}")

# vnc.html?app=chromium brings the browser to the front.
get(6080, "/vnc.html?app=chromium")
env = dict(os.environ, DISPLAY=":1")
t = time.monotonic()
while time.monotonic() - t < 20:
    out = subprocess.run(["wmctrl", "-lx"], env=env, capture_output=True, text=True).stdout
    if "chrom" in out.lower():
        break
    time.sleep(0.5)
ok("?app=chromium: the browser has a window") if "chrom" in out.lower() else bad(f"?app=chromium: no browser window: {out!r}")

log = open("/var/log/pyo-desktop.log").read()
ok(f"/var/log/pyo-desktop.log, {len(log.splitlines())} lines") if "listening on 6080" in log else bad("no /var/log/pyo-desktop.log")
raise SystemExit(fails)
PY
  if [ -n "$shot" ]; then
    # noVNC in a second, headless browser, which connects to the screen.
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

#!/usr/bin/env python3
"""The desktop image's desktop, started on first use.

/etc/pyo/start runs this when the sandbox boots. It listens on 127.0.0.1:
- 6080, the screen in voxl. Every request goes on to voxl, which listens
  on 127.0.0.1:6901 with a password only this program knows. The first
  request starts the screen (Xvfb), the session and voxl in the
  background. A request waits only for voxl. The browser starts once the
  screen is up, and nothing waits for it.
  The page at `/` (voxl's) or `/vnc.html` (where noVNC was, which goes on
  to `./`) asked with `?app=chromium` also brings the browser to the front,
  maximized: started when it isn't running, raised when it is.
- 9222, the browser's CDP: starts the screen and the browser (CDP on 9223)
  when it isn't running, then passes the connection to it.

Who may use 6080: Pyo's sandbox server passes it on only to whoever has
the sandbox's token, as `localhost:6080`. Programs in the sandbox (curl,
an agent asking for /screenshot or /wait) send no Origin and are let in
too. A web page open in the sandbox's own browser isn't: what it sends
carries the Origin of another site, and is let in only with the cookie
voxl's page gets here. A Host that isn't localhost or an IP address (a
domain made to point at 127.0.0.1) is turned away.

The browser is /usr/local/bin/browser: Google Chrome on amd64, Playwright's
Chromium on arm64 (see /etc/pyo/browser).

So a sandbox nobody looks at runs no X server, no voxl and no browser.
What it starts stays up, and is started again if it exited. It logs to
/var/log/pyo-desktop.log, with how long each start took.
"""

import asyncio
import ipaddress
import os
import secrets
import subprocess
import time
import urllib.parse

HOST = "127.0.0.1"
DISPLAY = ":1"
X_SOCKET = "/tmp/.X11-unix/X1"
SCREEN = 6080
VOXL = 6901
CDP, BROWSER_CDP = 9222, 9223
BROWSER = "/usr/local/bin/browser"
# What wmctrl -x finds the browser's windows by, in their WM_CLASS:
# google-chrome for Chrome, chromium for Chromium.
WM_CLASS = "chrom"
SIZE = "1280x800"
# voxl's password, new at every boot. This program adds it to what it
# passes on, so nothing reaches voxl without coming through here.
PASSWORD = secrets.token_urlsafe(32)
# The cookie voxl's page gets from here, which lets its requests in.
COOKIE = "pyo_desktop"
SESSION = secrets.token_urlsafe(32)
PAGES = ("/", "/index.html", "/vnc.html", "/vnc_lite.html")

procs: dict[str, subprocess.Popen] = {}
lock = asyncio.Lock()
browser_lock = asyncio.Lock()
browser_started = False
starting: asyncio.Task | None = None


def log(msg: str) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def env() -> dict:
    e = dict(os.environ)
    e.setdefault("HOME", "/root")
    e.setdefault("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
    e.setdefault("LANG", "C.UTF-8")
    e["DISPLAY"] = DISPLAY
    e["XDG_RUNTIME_DIR"] = "/tmp/runtime-root"
    return e


def alive(name: str) -> bool:
    p = procs.get(name)
    return p is not None and p.poll() is None


def spawn(name: str, args: list[str], extra: dict | None = None, logs: bool = False) -> None:
    log(f"starting {name}")
    os.makedirs("/tmp/runtime-root", mode=0o700, exist_ok=True)
    procs[name] = subprocess.Popen(
        args,
        env={**env(), **(extra or {})},
        cwd=env()["HOME"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        # Its warnings go to this program's log.
        stderr=None if logs else subprocess.DEVNULL,
        start_new_session=True,
    )


def stop(name: str) -> None:
    p = procs.pop(name, None)
    if p is not None and p.poll() is None:
        p.terminate()


async def answers(port: int) -> bool:
    try:
        _, w = await asyncio.open_connection(HOST, port)
    except OSError:
        return False
    w.close()
    return True


async def x_answers() -> bool:
    try:
        _, w = await asyncio.open_unix_connection(X_SOCKET)
    except OSError:
        return False
    w.close()
    return True


async def wait_for(check, secs: float, name: str) -> None:
    t = time.monotonic()
    while not await check():
        if time.monotonic() - t > secs:
            raise RuntimeError(f"{name} didn't start in {int(secs)}s")
        await asyncio.sleep(0.05)
    log(f"{name} is up in {int((time.monotonic() - t) * 1000)}ms")


async def screen() -> None:
    """The screen, its session and voxl, once."""
    async with lock:
        if not alive("screen"):
            # A new screen needs a new session and a new voxl.
            stop("voxl")
            procs.pop("session", None)
            # -shmem: voxl reads the screen straight from Xvfb's memory.
            spawn("screen", ["Xvfb", DISPLAY, "-screen", "0", f"{SIZE}x24", "-shmem", "-nolisten", "tcp", "-noreset"])
            await wait_for(x_answers, 20, "the screen")
        if not alive("session"):
            spawn("session", ["dbus-launch", "--exit-with-session", "/usr/local/lib/pyo-desktop/session"])
        if not alive("voxl"):
            spawn("voxl", [
                "voxl", "--addr", HOST, "--port", str(VOXL), "--title", "Desktop",
                # The sandbox has no sound, so no audio or microphone.
                "--audio-enabled=false", "--microphone-enabled=false",
                # Windows get rounded corners, maximized ones and menus
                # excepted, and so does the dock (tint2rc).
                "--round-corners", "10", "--round-windows", "tint2:18",
            ], {"VOXL_PASSWORD": PASSWORD, "RUST_LOG": "warn"}, logs=True)
            await wait_for(lambda: answers(VOXL), 20, "voxl")


async def browser() -> None:
    """The browser on the screen, with CDP up."""
    global browser_started
    await screen()
    # Its own lock: the screen never waits on the browser.
    async with browser_lock:
        browser_started = True
        if not await answers(BROWSER_CDP):
            if not alive("browser"):
                spawn("browser", [BROWSER, "--start-maximized", "about:blank"])
            await wait_for(lambda: answers(BROWSER_CDP), 60, "the browser")


async def desktop() -> None:
    """The screen, then (the first time someone looks) the browser on it."""
    await screen()
    if not browser_started:
        await browser()


async def wmctrl(*args: str) -> bool:
    p = await asyncio.create_subprocess_exec(
        "wmctrl", *args, env=env(),
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return await p.wait() == 0


async def front(app: str) -> None:
    """Brings an app to the front of the screen, maximized. Only the
    browser, asked for as chromium (or browser)."""
    if app not in ("chromium", "browser"):
        return
    await browser()
    t = time.monotonic()
    # Its window, once a browser that just started shows it. A new one in
    # the running browser when it has none.
    opened = False
    while not await wmctrl("-x", "-a", WM_CLASS):
        waited = time.monotonic() - t
        if waited > 15:
            log("the browser has no window to bring to the front")
            return
        if waited > 3 and not opened:
            spawn("browser window", [BROWSER, "--start-maximized", "about:blank"])
            opened = True
        await asyncio.sleep(0.1)
    await wmctrl("-x", "-r", WM_CLASS, "-b", "add,maximized_vert,maximized_horz")
    log(f"the browser is in front in {int((time.monotonic() - t) * 1000)}ms")


def start_desktop() -> asyncio.Task:
    """Starts the desktop in the background, once at a time."""
    global starting
    if starting is None or starting.done():
        starting = asyncio.ensure_future(desktop())
        starting.add_done_callback(lambda t: t.cancelled() or not t.exception() or log(f"couldn't start: {t.exception()}"))
    return starting


# ── 6080: voxl ───────────────────────────────────────────────────────────────


def reply(w: asyncio.StreamWriter, status: str, body: bytes, extra: list[str] | None = None) -> None:
    head = [
        f"HTTP/1.1 {status}",
        "Content-Type: text/plain; charset=utf-8",
        f"Content-Length: {len(body)}",
        "Cache-Control: no-store",
        "Connection: close",
        *(extra or []),
    ]
    w.write(("\r\n".join(head) + "\r\n\r\n").encode() + body)


Headers = list[tuple[str, str]]


async def read_head(r: asyncio.StreamReader) -> tuple[str, str, str, Headers] | None:
    try:
        raw = await asyncio.wait_for(r.readuntil(b"\r\n\r\n"), 30)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, OSError):
        return None
    lines = raw.decode("latin-1").split("\r\n")
    parts = lines[0].split(" ")
    if len(parts) != 3:
        return None
    headers = []
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers.append((k.strip(), v.strip()))
    return parts[0], parts[1], parts[2], headers


def header(headers: Headers, name: str) -> str | None:
    return next((v for k, v in headers if k.lower() == name), None)


def local_host(host: str | None) -> bool:
    """A Host that can't be a domain pointed at 127.0.0.1: localhost or an
    IP address. Programs that send none are let in."""
    if host is None:
        return True
    host = host.strip().lower()
    if host.startswith("["):
        name = host[1:].split("]", 1)[0]
    else:
        name = host.rsplit(":", 1)[0] if host.count(":") == 1 else host
    name = name.rstrip(".")
    if name == "localhost" or name.endswith(".localhost"):
        return True
    try:
        ipaddress.ip_address(name)
        return True
    except ValueError:
        return False


def has_cookie(headers: Headers) -> bool:
    for k, v in headers:
        if k.lower() != "cookie":
            continue
        for part in v.split(";"):
            name, _, value = part.strip().partition("=")
            if name == COOKIE and secrets.compare_digest(value.encode(), SESSION.encode()):
                return True
    return False


def turned_away(headers: Headers) -> str | None:
    """Why a request is turned away, or None to let it in."""
    host = header(headers, "host")
    if not local_host(host):
        return "The desktop answers only on localhost."
    origin = header(headers, "origin")
    if origin is None or has_cookie(headers):
        return None
    # A page this listener served itself, opened at the address it asks.
    u = urllib.parse.urlsplit(origin)
    if host and u.scheme in ("http", "https") and u.netloc.lower() == host.strip().lower():
        return None
    return "Open the desktop from Pyo."


async def handle_screen(r: asyncio.StreamReader, w: asyncio.StreamWriter) -> None:
    try:
        head = await read_head(r)
        if head is None:
            return
        method, target, version, headers = head
        split = urllib.parse.urlsplit(target)
        path = urllib.parse.unquote(split.path)
        query = urllib.parse.parse_qs(split.query)
        # Whatever is asked first, the screen starts now.
        start_desktop()
        why = turned_away(headers)
        if why is not None:
            log(f"turned away {method} {path}: {why}")
            reply(w, "403 Forbidden", why.encode() + b"\n")
            await w.drain()
            return
        page = path in PAGES
        if page and "app" in query:
            asyncio.ensure_future(front(query["app"][0])).add_done_callback(
                lambda t: t.cancelled() or not t.exception() or log(f"couldn't bring it to the front: {t.exception()}")
            )
        cookie = f"Set-Cookie: {COOKIE}={SESSION}; HttpOnly; SameSite=Lax"
        if path in ("/vnc.html", "/vnc_lite.html"):
            # Where noVNC was: voxl's page is next to it. The options were
            # noVNC's, so they stay behind.
            reply(w, "303 See Other", b"", ["Location: ./", cookie])
            await w.drain()
            return
        await to_voxl(r, w, method, target, version, headers, cookie if page else None)
    except (OSError, RuntimeError) as e:
        log(f"couldn't pass it on to voxl: {e}")
    finally:
        w.close()


async def to_voxl(r: asyncio.StreamReader, w: asyncio.StreamWriter, method: str, target: str,
                  version: str, headers: Headers, cookie: str | None) -> None:
    """Passes a request on to voxl, a WebSocket too, and its answer back."""
    try:
        await asyncio.shield(screen())
        vr, vw = await asyncio.open_connection(HOST, VOXL)
    except (OSError, RuntimeError) as e:
        log(f"couldn't reach voxl: {e}")
        reply(w, "503 Service Unavailable", b"The desktop didn't start.\n")
        await w.drain()
        return
    upgrade = (header(headers, "upgrade") or "").lower() == "websocket"
    # To voxl it's a program on its own address with its password: who it
    # comes from was checked here.
    out = [f"{method} {target} {version}", f"Host: {HOST}:{VOXL}", f"Authorization: Bearer {PASSWORD}"]
    for k, v in headers:
        if k.lower() not in ("host", "origin", "authorization", "connection", "keep-alive", "proxy-connection"):
            out.append(f"{k}: {v}")
    # One request per connection, so every request comes through here.
    out.append("Connection: Upgrade" if upgrade else "Connection: close")
    vw.write(("\r\n".join(out) + "\r\n\r\n").encode("latin-1"))
    await vw.drain()

    async def up() -> None:
        try:
            while data := await r.read(1 << 16):
                vw.write(data)
                await vw.drain()
            if vw.can_write_eof():
                vw.write_eof()
        except (OSError, RuntimeError):
            pass

    async def down() -> None:
        try:
            if cookie:
                # voxl's page: the cookie goes in with its answer.
                res = await asyncio.wait_for(vr.readuntil(b"\r\n\r\n"), 30)
                w.write(res[:-2] + cookie.encode() + b"\r\n\r\n")
            while data := await vr.read(1 << 16):
                w.write(data)
                await w.drain()
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, OSError, RuntimeError):
            pass

    upward = asyncio.ensure_future(up())
    await down()
    upward.cancel()
    vw.close()


# ── 9222: the browser's CDP ──────────────────────────────────────────────────


async def pipe(r: asyncio.StreamReader, w: asyncio.StreamWriter) -> None:
    try:
        while data := await r.read(1 << 16):
            w.write(data)
            await w.drain()
        if w.can_write_eof():
            w.write_eof()
    except (OSError, RuntimeError):
        pass


async def handle_cdp(cr: asyncio.StreamReader, cw: asyncio.StreamWriter) -> None:
    try:
        await browser()
        tr, tw = await asyncio.open_connection(HOST, BROWSER_CDP)
    except Exception as e:  # noqa: BLE001 - log it, drop the connection
        log(f"couldn't start: {e}")
        cw.close()
        return
    await asyncio.gather(pipe(cr, tw), pipe(tr, cw))
    for w in (tw, cw):
        w.close()


async def main() -> None:
    servers = [
        await asyncio.start_server(handle_screen, HOST, SCREEN, reuse_address=True),
        await asyncio.start_server(handle_cdp, HOST, CDP, reuse_address=True),
    ]
    log(f"listening on {SCREEN} (screen) and {CDP} (CDP)")
    await asyncio.gather(*(s.serve_forever() for s in servers))


if __name__ == "__main__":
    asyncio.run(main())

# Pyo Sandbox images

The images [Pyo](https://github.com/upsetdev/pyo) sandboxes start from. Both are Ubuntu 24.04 LTS, built for linux/amd64 and linux/arm64, in the spirit of GitHub Actions runners.

| Image | What it is |
| --- | --- |
| `ghcr.io/upsetdev/pyo-sandbox-images/base` | A lean dev machine with the tools coding agents expect |
| `ghcr.io/upsetdev/pyo-sandbox-images/desktop` | `base` with a desktop you can watch and use in voxl and a browser agents drive over CDP |

Tags:

- `24.04` is the latest build.
- `24.04-YYYYMMDD` is the build of that day.
- The full git sha is the build of that commit.

Every image is signed with cosign keyless by this repo's release workflow. Each release also has `images.json`, which lists every image's digest per tag and the contract version, signed the same way.

```sh
cosign verify ghcr.io/upsetdev/pyo-sandbox-images/base:24.04 \
  --certificate-identity-regexp '^https://github.com/upsetdev/pyo-sandbox-images/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## base

| Tool | Version | From |
| --- | --- | --- |
| Ubuntu | 24.04 LTS | `ubuntu:24.04`, pinned by digest, upgraded at each build |
| git, curl, wget, jq, ripgrep, zip, unzip, xz, less, vim (tiny), nano, openssh-client, rsync, gnupg, procps, iproute2, ping, dig, netcat, lsof, file, sudo | Ubuntu's | Ubuntu |
| build-essential, pkg-config, cmake, ninja | Ubuntu's | Ubuntu |
| Python 3.12 with pip, venv and headers | Ubuntu's | Ubuntu |
| uv, uvx | 0.13.8 | Astral's image |
| Node.js with npm | 24.22.3 LTS | nodejs.org |
| pnpm | 12.21.0 | corepack 0.36.0 |
| Bun | 1.4.4 | GitHub release |
| Deno | 2.9.8 | GitHub release |
| GitHub CLI `gh` | 2.104.0 | GitHub's apt repository |
| Docker CLI, buildx, compose | 29.10.0, 0.39.0, 5.7.1 | Docker's apt repository |
| Claude Code `claude` | 2.1.325 | npm |
| Codex `codex` | 0.169.0 | npm |
| opencode `opencode` | 1.19.5 | npm |

The Docker CLI has no daemon in the image. Point it at one with `DOCKER_HOST`.

Locales: `C.UTF-8` (the default) and `en_US.UTF-8`.

pip installs into the system Python, as agents expect: a sandbox is thrown away.

On amd64 it's about 3.3 GB unpacked and 0.9 GB to pull. About 1.1 GB of that is the three agent CLIs, which each ship one large native binary. `desktop` adds about 1.25 GB unpacked and 0.35 GB to pull.

## desktop

Everything in `base`, plus:

- Xvfb, Openbox, a tint2 dock, xfce4-terminal and the PCManFM file manager
- [voxl](https://github.com/tembo/voxl) 0.3.5, built from source against Ubuntu's x264, libyuv and Opus, with Pyo's changes to its web page (`images/desktop/voxl/patches`). It streams the screen as H.264 to its web page, which decodes it with WebCodecs, so the page has to be on HTTPS or localhost
- Fonts: Inter for the desktop, JetBrains Mono for the terminal, DejaVu, Liberation, Noto Color Emoji and Droid Sans Fallback for CJK
- wmctrl and xdotool
- One browser, which depends on the architecture

| Architecture | Browser |
| --- | --- |
| amd64 | Google Chrome stable, from Google's apt repository |
| arm64 | Chromium from Playwright 1.65.1, as Google has no Chrome for Linux on arm64 |

Either one runs as `browser`, also named `google-chrome` and `chromium`. That wrapper adds the flags a sandbox needs: `--no-sandbox` for root, no first run, no default browser check, no background networking or component updates, and CDP on 127.0.0.1:9223. Flags you pass after them win. `/etc/pyo/browser` says which browser it is, its version and its path.

Chrome's version isn't pinned, as Google's repository only keeps the latest. The weekly build picks it up.

The desktop looks like Pyo:

- A dock centered at the bottom with the terminal, the browser and the file manager, the open windows and a clock. voxl rounds its corners and the windows', so there's no compositor.
- Pyo's wallpaper and icons, drawn as SVG in `images/desktop/art` and `images/desktop/icons`. The build renders the wallpaper and the page's ICO.
- An Openbox theme of its own (`images/desktop/openbox`), GTK's Adwaita in its dark variant with Inter, and a terminal in JetBrains Mono with Pyo's colors. The browser keeps its light theme, so web pages look as they do anywhere.
- voxl's page has Pyo's icon and loading screen, and its title names the sandbox: `Desktop | <name>`, from `?name=`.

Managed policies (`images/desktop/policy.json`, in `/etc/opt/chrome/policies/managed` and `/etc/chromium/policies/managed`) turn off sign-in, sync and metrics, and the prompts that get in an agent's way: default browser, saving passwords, translating, promotions and surveys. `chrome://policy` lists them.

## Pyo's contract

Every image carries the label `dev.pyo.sandbox.contract="1"`. Contract 1 means:

- Pyo's pyo-envd runs every command as root in `/root`, with `HOME=/root`, `LANG=C.UTF-8`, `TERM=xterm-256color` and `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`. It doesn't use the image's `User`, `Env`, `WorkingDir`, `Entrypoint` or `Cmd`. So every tool works as root with that PATH, and nothing relies on the image's ENV.
- The image has `/proc`, `/sys`, `/dev`, `/tmp`, `/run`, `/mnt` and `/root`. Pyo mounts the sandbox's writable disk on `/mnt` before it switches root.
- When `/etc/pyo/start` is an executable file, pyo-envd runs it once at boot, in a session of its own. `base` has none.
- `desktop`'s `/etc/pyo/start` starts only a small listener (`desktop.py`) and logs to `/var/log/pyo-desktop.log`. It listens on 127.0.0.1:
  - 6080 is voxl: its page at `/`, its WebSocket at `/ws` and its API (`/screenshot`, `/wait`, `/record`, `/files`). desktop.py passes each request on to voxl on 127.0.0.1:6901, which has a password only desktop.py knows.
  - 9222 is the browser's CDP, passed on to the browser itself on 9223.
- Nothing else starts until it's used. The first request on either port starts the screen, then voxl and the browser.
- `vnc.html`, where noVNC's page was, goes on to `./`, voxl's page. `?app=chromium` on either one also brings the browser to the front, maximized. `?name=` (the sandbox's name) goes on with it and ends up in the page's title, `Desktop | <name>`. Without it the title is `Desktop`.
- 6080 lets in what Pyo's sandbox server passes on (as `localhost:6080`) and programs in the sandbox, which send no `Origin`. A page of another site in the sandbox's browser is turned away, unless it has the cookie voxl's page gets from 6080. So is a `Host` that isn't localhost or an IP address.

Programs in the sandbox can use voxl's API through 6080 with no password:

```sh
curl -o shot.png localhost:6080/screenshot   # the screen as a PNG
curl localhost:6080/wait                     # once the screen settles
```

A change Pyo would notice gets a new contract number.

Pyo runs sandboxes as root, so the images do too. There's no `runner` user with sudo like GitHub's runners. `sudo` is installed for scripts that call it.

## Build locally

```sh
docker buildx build --platform linux/amd64 --load --build-context notices=. \
  -t pyo-sandbox/base:local images/base
docker buildx build --platform linux/amd64 --load --build-context notices=. \
  --build-arg BASE=pyo-sandbox/base:local -t pyo-sandbox/desktop:local images/desktop

scripts/smoke.sh base pyo-sandbox/base:local
scripts/smoke.sh desktop pyo-sandbox/desktop:local out/desktop.png
```

`--build-context notices=.` gives the build THIRD_PARTY_NOTICES.md, which both images carry. Use `--platform linux/arm64` for arm64. It needs an arm64 machine or QEMU. `desktop` builds voxl with Rust: `--build-arg CARGO_BUILD_JOBS=4` uses less memory.

`smoke.sh` runs commands the way pyo-envd does and prints every tool's version. For `desktop` it starts `/etc/pyo/start`, then checks `vnc.html` (with `?name=`) and voxl's page with Pyo's changes and icons, its WebSocket (101, then voxl's hello) and who it lets in, voxl's screenshot (not black) and `/wait`, CDP's `/json/version`, `?app=chromium` with the browser maximized, the dock and the notices. With a path it saves a screenshot of voxl's page as a viewer sees it.

## Versions

- Every version is a build arg at the top of its Dockerfile. Updating one is a one-line change.
- Downloads are checked against the sha256 their project publishes. apt repositories are checked against their key's fingerprint. Images are pinned by digest.
- Pull requests build both images on both architectures and run `smoke.sh`, each architecture on a runner of its own.
- Every push to `main` publishes. So does a weekly build, which picks up Ubuntu's security updates and the latest Chrome.

## Licenses

This repo's own files are Apache 2.0, like Pyo. The images bundle software under other licenses, including the GPL (voxl's binary, as it links x264, which is GPL). [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) lists each one with its version, license and source. Both images carry it in `/usr/share/doc/pyo-sandbox-images`, and the label `dev.pyo.sandbox.notices` points to it. voxl's license, copyright, source and Pyo's patches to it are in `/usr/share/doc/voxl`. Every release here has voxl's source with those patches applied (the patches are in it too) and the Rust crates built into it as tarballs, which build offline together.

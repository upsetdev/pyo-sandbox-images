# Third-party notices

The files in this repository are Apache 2.0 (see the README). The images built from them bundle software made by others, under its own licenses. This file lists every component the images ship that isn't a plain Ubuntu package, with its version, license and source.

Ubuntu 24.04 and every package installed from Ubuntu's archive keep their licenses in `/usr/share/doc/<package>/copyright` inside the image. Packages from other apt repositories (GitHub CLI, Docker, Google Chrome) are listed below.

Both images carry a copy of this file in `/usr/share/doc/pyo-sandbox-images/THIRD_PARTY_NOTICES.md`, and the label `dev.pyo.sandbox.notices` points to it. Versions are those this repository pins. The weekly build takes Ubuntu's security updates and the latest Chrome, so `/usr/share/doc/voxl/SOURCE` and each release's notes give the exact x264, libyuv and Opus versions of that build.

## base

| Component | Version | License | Source |
| --- | --- | --- | --- |
| uv, uvx | 0.13.8 | MIT or Apache-2.0 | https://github.com/astral-sh/uv |
| Node.js | 24.22.3 | MIT, with what it bundles under the licenses in its LICENSE file (`/usr/share/doc/nodejs/LICENSE`) | https://nodejs.org, https://github.com/nodejs/node |
| npm (bundled with Node.js) | the one in Node.js 24.22.3 | Artistic-2.0 | https://github.com/npm/cli |
| corepack | 0.36.0 | MIT | https://github.com/nodejs/corepack |
| pnpm | 12.21.0 | MIT | https://github.com/pnpm/pnpm |
| Bun | 1.4.4 | MIT. It includes JavaScriptCore and parts of WebKit, which are LGPL-2.0, and other libraries listed at https://bun.sh/docs/project/licensing | https://github.com/oven-sh/bun |
| Deno | 2.9.8 | MIT, with V8 (BSD-3-Clause) and other libraries | https://github.com/denoland/deno |
| GitHub CLI `gh` (GitHub's apt repository) | 2.104.0 | MIT | https://github.com/cli/cli |
| Docker CLI `docker-ce-cli` (Docker's apt repository) | 29.10.0 | Apache-2.0 | https://github.com/docker/cli |
| Docker Buildx `docker-buildx-plugin` (Docker's apt repository) | 0.39.0 | Apache-2.0 | https://github.com/docker/buildx |
| Docker Compose `docker-compose-plugin` (Docker's apt repository) | 5.7.1 | Apache-2.0 | https://github.com/docker/compose |
| Claude Code `@anthropic-ai/claude-code` | 2.1.325 | Proprietary: © Anthropic PBC, all rights reserved. Use is subject to the legal agreements at https://code.claude.com/docs/en/legal-and-compliance (its `LICENSE.md` in `/usr/local/lib/node_modules/@anthropic-ai/claude-code`) | https://github.com/anthropics/claude-code |
| Codex `@openai/codex` | 0.169.0 | Apache-2.0 | https://github.com/openai/codex |
| opencode `opencode-ai` | 1.19.5 | MIT | https://www.npmjs.com/package/opencode-ai |

The npm packages keep their license files in `/usr/local/lib/node_modules/<package>`.

## desktop

Everything in base, plus:

| Component | Version | License | Source |
| --- | --- | --- | --- |
| voxl | 0.3.5, commit `93ad2d4839a3d1a9086a07307bfe66baa75f2504`, with Pyo's changes to its web page (`images/desktop/voxl/patches`) | voxl's code is MIT, and so are Pyo's changes to it. Its binary links x264, so the binary is distributed under the GPL, version 2 or later | https://github.com/tembo/voxl, and `voxl-0.3.5-93ad2d4839a3-patched.tar.gz` (with the patches applied, and in its `pyo-patches` folder) in every release of this repository |
| The Rust crates built into voxl | as voxl's `Cargo.lock` pins them | Mostly MIT or Apache-2.0. Each one is listed with its license in `/usr/share/doc/voxl/crates/README.md`, with its license files | https://crates.io, and `voxl-0.3.5-93ad2d4839a3-vendor.tar.gz` (cargo vendor) in every release of this repository |
| Inter, the font voxl's page embeds | the one in voxl 0.3.5 | SIL Open Font License 1.1 | https://github.com/rsms/inter |
| Inter, the desktop's font (`fonts-inter-variable`, Ubuntu's archive) | Ubuntu's | SIL Open Font License 1.1 (`/usr/share/doc/fonts-inter-variable/copyright`) | https://github.com/rsms/inter |
| JetBrains Mono, the terminal's font (`fonts-jetbrains-mono`, Ubuntu's archive) | Ubuntu's | Apache-2.0, as Ubuntu's package states it (`/usr/share/doc/fonts-jetbrains-mono/copyright`) | https://github.com/JetBrains/JetBrainsMono |
| x264 (`libx264-164`, Ubuntu's archive) | 2:0.164.3108+git31e19f9-1 | GPL-2.0-or-later | Ubuntu's source package `x264`: https://launchpad.net/ubuntu/+source/x264 |
| libyuv (`libyuv0`, Ubuntu's archive) | 0.0~git202401110.af6ac82-1 | BSD-3-Clause | Ubuntu's source package `libyuv`: https://launchpad.net/ubuntu/+source/libyuv |
| Opus (`libopus0`, Ubuntu's archive) | 1.4-1build1 | BSD-3-Clause | Ubuntu's source package `opus`: https://launchpad.net/ubuntu/+source/opus |
| Google Chrome `google-chrome-stable` (amd64 only, Google's apt repository) | the latest stable at build time, in `/etc/pyo/browser` | Proprietary: Google Chrome Terms of Service (https://www.google.com/chrome/terms/). Its open source parts are listed at `chrome://credits` | https://www.google.com/chrome/ |
| Chromium from Playwright (arm64 only) | the build Playwright 1.65.1 installs, in `/etc/pyo/browser` | BSD-3-Clause, with the third-party software listed at `chrome://credits` | https://github.com/microsoft/playwright, https://www.chromium.org |

voxl's license, its copyright, the source it was built from, Pyo's patches to it and the crates' licenses are in `/usr/share/doc/voxl`. x264, libyuv and Opus come from Ubuntu's archive, which publishes their source (`apt-get source x264 libyuv opus`). Their copyright files are in `/usr/share/doc/libx264-164`, `/usr/share/doc/libyuv0` and `/usr/share/doc/libopus0`. The GPL's text is in `/usr/share/common-licenses/GPL-2`.

The build also uses Rust (through rustup) and esbuild 0.25.12 (MIT) to compile voxl, Ubuntu's librsvg (`rsvg-convert`) to render the wallpaper and the page's icon, and gcc with GTK's and libwnck's headers to compile the dock. They stay in the build and aren't in the image.

The desktop's look and its dock are this repository's own work, under its Apache 2.0 license: the dock (`images/desktop/dock/pyo-dock.c`), the wallpaper, the dock's terminal and file manager icons and the page's icons (`images/desktop/art`, `images/desktop/icons`, from Pyo's logo), the Openbox theme (`images/desktop/openbox`) and the GTK stylesheet (`images/desktop/gtk`). The rest of the desktop comes from Ubuntu's archive, each package with its license in `/usr/share/doc/<package>/copyright`: Openbox (GPL-2.0-or-later), libwnck, which the dock links (LGPL-2.0-or-later), xfce4-terminal (GPL-2.0-or-later), PCManFM and libfm (GPL-2.0-or-later), xwallpaper (ISC), the Adwaita icon theme (LGPL-3.0 or CC-BY-SA-3.0) and the GTK theme in GTK itself (LGPL-2.1-or-later).

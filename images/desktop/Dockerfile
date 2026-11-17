# Pyo Sandbox image `desktop`: `base` with a desktop and a browser.
#
# One image, two uses:
# - Agents drive the browser over CDP at 127.0.0.1:9222 in the sandbox.
# - People see and use the screen through voxl at 127.0.0.1:6080.
#
# Nothing runs until it's used. pyo-envd runs /etc/pyo/start at boot,
# which starts only a small listener on 6080 and 9222 (desktop.py). The
# first use of either port starts the screen (Xvfb) with Openbox and a
# dock of its own (dock/pyo-dock.c), then voxl, then the browser. desktop.py passes 6080 on to
# voxl (127.0.0.1:6901, with a password only desktop.py knows) and 9222 to
# the browser's CDP on 9223, all on 127.0.0.1 only. It logs to
# /var/log/pyo-desktop.log.
#
# voxl streams the screen as H.264 over a WebSocket to its page, which
# decodes it with WebCodecs. It's built from source in its own stage below,
# against Ubuntu's x264, libyuv and Opus, with Pyo's changes to its page
# (voxl/patches). The final image has its binary and those libraries, no
# build tools.
#
# The look: Pyo's wallpaper and icons (art, icons), an Openbox theme
# (openbox), the dock (dock), GTK's dark Adwaita with Pyo's colors and
# Inter (gtk), the file manager's defaults (files) and the terminal's
# colors and font (xfce4-terminal.xml).
#
# The browser depends on the architecture, one per image: Google Chrome
# on amd64 (Google has no Linux arm64 build), Playwright's Chromium on
# arm64. Both run as /usr/local/bin/browser, also named google-chrome and
# chromium. /etc/pyo/browser says which one it is.
#
# Everything runs as root, like the rest of the sandbox, so the browser
# runs with --no-sandbox: the sandbox itself is the isolation.
#
# Third-party software and its licenses: THIRD_PARTY_NOTICES.md, also in
# /usr/share/doc/pyo-sandbox-images in the image. The build needs it as the
# named context `notices` (the repo's root): --build-context notices=.

ARG BASE=ghcr.io/upsetdev/pyo-sandbox-images/base:24.04
ARG PLAYWRIGHT_VERSION=1.65.1
# voxl's release tag and the commit it points at, checked at build.
ARG VOXL_VERSION=0.3.5
ARG VOXL_COMMIT=93ad2d4839a3d1a9086a07307bfe66baa75f2504
# What builds it: Rust through rustup (checked against its sha256 per
# architecture) and esbuild, which bundles voxl's web page.
ARG RUST_VERSION=1.99.1
ARG RUSTUP_VERSION=1.28.2
ARG RUSTUP_SHA256_AMD64=20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c
ARG RUSTUP_SHA256_ARM64=e3853c5a252fca15252d07cb23a1bdd9377a8c6f3efa01531109281ae47f841c
ARG ESBUILD_VERSION=0.25.12

# ── voxl, built from source ─────────────────────────────────────────────────
# On base, so its libraries are the same Ubuntu versions as the final
# image's. Without PulseAudio (no desktop audio): the image has no sound.
FROM ${BASE} AS voxl
ARG VOXL_VERSION VOXL_COMMIT RUST_VERSION RUSTUP_VERSION \
    RUSTUP_SHA256_AMD64 RUSTUP_SHA256_ARM64 ESBUILD_VERSION
ARG TARGETARCH
# Fewer parallel jobs on a machine short of memory. Empty: one per CPU.
ARG CARGO_BUILD_JOBS=""
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      clang libclang-dev libopus-dev libx264-dev libyuv-dev; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) triple=x86_64-unknown-linux-gnu; sum=$RUSTUP_SHA256_AMD64 ;; \
      arm64) triple=aarch64-unknown-linux-gnu; sum=$RUSTUP_SHA256_ARM64 ;; \
      *) echo "No Rust for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSLo /tmp/rustup-init "https://static.rust-lang.org/rustup/archive/$RUSTUP_VERSION/$triple/rustup-init"; \
    echo "$sum  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION"; \
    rm /tmp/rustup-init; \
    npm install -g "esbuild@$ESBUILD_VERSION"; \
    rustc --version; cargo --version; esbuild --version

# The release tag, checked against the commit it should point at.
RUN set -eux; \
    git init -q /src/voxl; \
    cd /src/voxl; \
    git fetch -q --depth 1 https://github.com/tembo/voxl "refs/tags/v$VOXL_VERSION:refs/tags/v$VOXL_VERSION"; \
    [ "$(git rev-parse "v$VOXL_VERSION^{commit}")" = "$VOXL_COMMIT" ]; \
    git -c advice.detachedHead=false checkout -q "$VOXL_COMMIT"

WORKDIR /src/voxl
# Pyo's changes, to its web page only. They go in the docs below, and
# every release has the source with them.
COPY voxl/patches /src/patches
RUN set -eux; \
    for p in /src/patches/*.patch; do git apply "$p"; done; \
    git status --short
COPY voxl-licenses.py /usr/local/bin/voxl-licenses.py
RUN set -eux; \
    cargo build --release --locked --no-default-features ${CARGO_BUILD_JOBS:+--jobs "$CARGO_BUILD_JOBS"}; \
    install -D -m 0755 target/release/voxl /out/bin/voxl; \
    strip /out/bin/voxl; \
    /out/bin/voxl --version; \
    # Its docs: license, copyright, where the source is, and the crates
    # built into it with their licenses.
    doc=/out/doc; \
    install -d "$doc/patches"; \
    cp LICENSE "$doc/LICENSE"; \
    cp /src/patches/*.patch "$doc/patches/"; \
    cp web/inter-LICENSE.txt "$doc/inter-LICENSE.txt"; \
    python3 -I /usr/local/bin/voxl-licenses.py "$doc/crates" --no-default-features; \
    deb() { dpkg-query -W -f '${source:Package} ${source:Version}' "$1"; }; \
    { \
      echo "voxl $VOXL_VERSION"; \
      echo; \
      echo "Source: https://github.com/tembo/voxl"; \
      echo "Tag: v$VOXL_VERSION"; \
      echo "Commit: $VOXL_COMMIT"; \
      echo "Tarball: https://github.com/tembo/voxl/archive/$VOXL_COMMIT.tar.gz"; \
      echo; \
      echo "Changed for Pyo: its web page only (the icons, the tab's title and two"; \
      echo "messages). The changes are the patches in patches/ here, applied"; \
      echo "in order with git apply to that commit. They're also in"; \
      echo "images/desktop/voxl/patches in https://github.com/upsetdev/pyo-sandbox-images."; \
      echo; \
      echo "Every release of that repository has the source with the patches applied"; \
      echo "as voxl-$VOXL_VERSION-${VOXL_COMMIT:0:12}-patched.tar.gz, with the patches in its"; \
      echo "pyo-patches folder, and the Rust crates built into it as"; \
      echo "voxl-$VOXL_VERSION-${VOXL_COMMIT:0:12}-vendor.tar.gz (cargo vendor). Unpacked in one"; \
      echo "folder, the two build offline."; \
      echo; \
      echo "Built with Rust $RUST_VERSION and esbuild $ESBUILD_VERSION:"; \
      echo "  cargo build --release --locked --no-default-features"; \
      echo "The build is images/desktop/Dockerfile in that repository."; \
      echo; \
      echo "Linked with these libraries from Ubuntu's archive, by source package and"; \
      echo "version. apt-get source gets their source:"; \
      echo "  $(deb libx264-dev)"; \
      echo "  $(deb libyuv-dev)"; \
      echo "  $(deb libopus-dev)"; \
    } > "$doc/SOURCE"; \
    { \
      echo "voxl $VOXL_VERSION, https://github.com/tembo/voxl"; \
      echo; \
      echo "voxl's own code: MIT License, Copyright (c) 2026 Tembo. See LICENSE."; \
      echo "Pyo's changes to it (patches/) are under the same license."; \
      echo; \
      echo "This binary links x264, which is GPL-2.0-or-later, so the binary is"; \
      echo "distributed under the GNU General Public License, version 2 or later."; \
      echo "Its text is in /usr/share/common-licenses/GPL-2. SOURCE says where the"; \
      echo "source is."; \
      echo; \
      echo "It also links libyuv (BSD-3-Clause) and Opus (BSD-3-Clause). Their"; \
      echo "copyright files: /usr/share/doc/libx264-164/copyright,"; \
      echo "/usr/share/doc/libyuv0/copyright and /usr/share/doc/libopus0/copyright."; \
      echo; \
      echo "Its web page embeds the Inter font, SIL Open Font License 1.1. See"; \
      echo "inter-LICENSE.txt."; \
      echo; \
      echo "The Rust crates built into it: crates/README.md, with each crate's"; \
      echo "license files."; \
    } > "$doc/copyright"

# ── The desktop's art ───────────────────────────────────────────────────────
# The wallpaper and the page's icons, rendered from the SVGs in art.
FROM ${BASE} AS art
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends librsvg2-bin; \
    rm -rf /var/lib/apt/lists/*
COPY art /art
RUN sh /art/build.sh /out

# ── The dock ────────────────────────────────────────────────────────────────
# pyo-dock, a small GTK program (dock/pyo-dock.c) with libwnck.
FROM ${BASE} AS dock
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends libgtk-3-dev libwnck-3-dev; \
    rm -rf /var/lib/apt/lists/*
COPY dock/pyo-dock.c /src/pyo-dock.c
RUN set -eux; \
    mkdir -p /out; \
    gcc -O2 -Wall -Wextra -Wno-unused-parameter -Werror -o /out/pyo-dock /src/pyo-dock.c \
      $(pkg-config --cflags --libs gtk+-3.0 libwnck-3.0 x11); \
    strip /out/pyo-dock

# ── The image ───────────────────────────────────────────────────────────────
FROM ${BASE}
ARG PLAYWRIGHT_VERSION
ARG TARGETARCH
LABEL org.opencontainers.image.source=https://github.com/upsetdev/pyo-sandbox-images \
      org.opencontainers.image.title="Pyo Sandbox desktop" \
      org.opencontainers.image.description="Pyo Sandbox base with a desktop in voxl and a browser with CDP" \
      org.opencontainers.image.licenses=Apache-2.0 \
      dev.pyo.sandbox.notices=/usr/share/doc/pyo-sandbox-images/THIRD_PARTY_NOTICES.md \
      dev.pyo.sandbox.contract="1"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# The screen, the window manager, the dock's library (libwnck), a
# terminal, a file manager (PCManFM), the wallpaper's setter and fonts,
# and the libraries voxl links. Droid Sans Fallback covers CJK at a fraction of Noto CJK's size.
# Inter (variable) is the desktop's font, JetBrains Mono the terminal's.
# librsvg2-common lets GTK apps load SVG icons.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      dbus-x11 fonts-dejavu-core fonts-droid-fallback fonts-inter-variable \
      fonts-jetbrains-mono fonts-liberation fonts-noto-color-emoji \
      libopus0 librsvg2-common libwnck-3-0 libx264-164 libyuv0 openbox pcmanfm \
      wmctrl x11-xserver-utils xdg-utils xdotool xfce4-terminal xvfb \
      xwallpaper; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

# The browser, one per architecture. Its name, version and path go to
# /etc/pyo/browser, which /usr/local/bin/browser reads.
COPY browser /usr/local/bin/browser
COPY browser.desktop.in /tmp/browser.desktop.in
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) \
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub -o /tmp/key; \
        gpg --show-keys --with-colons /tmp/key | grep -q '^fpr:::::::::EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796:'; \
        install -d -m 0755 /etc/apt/keyrings; \
        gpg --dearmor < /tmp/key > /etc/apt/keyrings/google-chrome.gpg; \
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
          > /etc/apt/sources.list.d/google-chrome.list; \
        apt-get update; \
        apt-get install -y --no-install-recommends google-chrome-stable; \
        # Chrome's package adds its key and repository again its own way.
        rm -f /etc/apt/trusted.gpg.d/google-chrome.gpg /etc/cron.daily/google-chrome; \
        path=/opt/google/chrome/google-chrome; \
        icon=google-chrome; wmclass=Google-chrome; \
        # Its own menu entry starts it through the wrapper too.
        sed -i 's#^Exec=/usr/bin/google-chrome-stable#Exec=/usr/local/bin/browser#' \
          /usr/share/applications/google-chrome.desktop; \
        ;; \
      arm64) \
        export PLAYWRIGHT_BROWSERS_PATH=/opt/playwright; \
        npx -y "playwright@$PLAYWRIGHT_VERSION" install --with-deps --no-shell chromium; \
        path=$(find /opt/playwright -type f -name chrome -path '*/chrome-linux*/*' | head -n1); \
        [ -x "$path" ]; \
        wmclass=Chromium; \
        icon="$(dirname "$path")/product_logo_48.png"; \
        [ -f "$icon" ] || icon=web-browser; \
        npm cache clean --force; \
        rm -rf /root/.npm; \
        ;; \
      *) echo "No browser for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    # "Google Chrome 157.0.8103.78", "Chromium 159.0.8154.6".
    about=$("$path" --version); \
    version=$(echo "$about" | grep -oE '[0-9]+(\.[0-9]+){3}' | head -n1); \
    name=$(echo "$about" | sed -E 's/ *[0-9]+(\.[0-9]+){3}.*$//'); \
    mkdir -p /etc/pyo; \
    printf '# The desktop browser, which /usr/local/bin/browser runs.\nBROWSER_NAME="%s"\nBROWSER_VERSION="%s"\nBROWSER_PATH="%s"\n' \
      "$name" "$version" "$path" > /etc/pyo/browser; \
    sed -e "s#@NAME@#$name#" -e "s#@ICON@#$icon#" -e "s#@WMCLASS@#$wmclass#" \
      /tmp/browser.desktop.in > /usr/share/applications/browser.desktop; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/*; \
    chmod 0755 /usr/local/bin/browser; \
    for n in google-chrome google-chrome-stable chromium chromium-browser; do \
      ln -sf browser "/usr/local/bin/$n"; \
    done; \
    # Links from the terminal open it too.
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/browser 300; \
    update-alternatives --set x-www-browser /usr/local/bin/browser; \
    cat /etc/pyo/browser; \
    browser --version

# The browser's managed policies: no sign-in or sync, and no prompts that
# get in an agent's way (default browser, saving passwords, translating,
# promotions, surveys). No metrics, and no on-device AI model to download.
# Chrome reads them from /etc/opt/chrome, Chromium from /etc/chromium.
COPY policy.json /etc/opt/chrome/policies/managed/pyo.json
COPY policy.json /etc/chromium/policies/managed/pyo.json

# voxl, from its stage above, with its license, copyright and source.
COPY --from=voxl /out/bin/voxl /usr/local/bin/voxl
COPY --from=voxl /out/doc /usr/share/doc/voxl
# Every library it needs is here.
RUN set -eux; \
    if ldd /usr/local/bin/voxl | grep 'not found'; then exit 1; fi; \
    voxl --version

# Third-party software in the image and its licenses.
COPY --from=notices THIRD_PARTY_NOTICES.md /usr/share/doc/pyo-sandbox-images/THIRD_PARTY_NOTICES.md

# The look. Openbox's theme, and its rc.xml set to use it (openbox/rc.py).
COPY openbox/themerc openbox/*.xbm /usr/share/themes/Pyo/openbox-3/
COPY openbox/rc.py /tmp/rc.py
RUN python3 -I /tmp/rc.py /etc/xdg/openbox/rc.xml && rm /tmp/rc.py
# Pyo's icons for the terminal and the file manager, Adwaita's for the rest.
COPY icons/index.theme /usr/share/icons/Pyo/index.theme
COPY icons/terminal.svg /usr/share/icons/Pyo/scalable/apps/org.xfce.terminal.svg
COPY icons/files.svg /usr/share/icons/Pyo/scalable/apps/system-file-manager.svg
RUN set -eux; \
    cd /usr/share/icons/Pyo/scalable/apps; \
    ln -s org.xfce.terminal.svg utilities-terminal.svg; \
    gtk-update-icon-cache -q /usr/share/icons/Pyo
# GTK, the terminal, the file manager and the dock.
COPY gtk/settings.ini /etc/gtk-3.0/settings.ini
COPY gtk/gtk.css /usr/share/themes/Pyo/gtk-3.0/gtk.css
COPY xfce4-terminal.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml
COPY files/pcmanfm.conf /etc/xdg/pcmanfm/default/pcmanfm.conf
COPY files/libfm.conf /etc/xdg/libfm/libfm.conf
COPY dock/terminal.desktop dock/files.desktop /usr/local/share/pyo-desktop/dock/
COPY --from=dock /out/pyo-dock /usr/local/bin/pyo-dock
# The wallpaper and the page's icons, which desktop.py serves.
COPY --from=art /out /usr/local/share/pyo-desktop

COPY start /etc/pyo/start
COPY desktop.py /usr/local/lib/pyo-desktop/desktop.py
COPY session /usr/local/lib/pyo-desktop/session

RUN chmod 755 /etc/pyo/start /usr/local/lib/pyo-desktop/session \
    && python3 -m py_compile /usr/local/lib/pyo-desktop/desktop.py

WORKDIR /root
CMD ["bash"]

# Pyo Sandbox image `desktop`: `base` with a desktop and a browser.
#
# One image, two uses:
# - Agents drive the browser over CDP at 127.0.0.1:9222 in the sandbox.
# - People see the screen through noVNC at 127.0.0.1:6080.
#
# Nothing runs until it's used. pyo-envd runs /etc/pyo/start at boot,
# which starts only a small listener on 6080 and 9222 (desktop.py). It
# serves noVNC's files and WebSocket on 6080 itself. The first use of
# either port starts the screen (TigerVNC's Xvnc) with Openbox and a tint2
# panel, then the browser. The browser's CDP is on 9223 behind 9222, VNC
# on 5901, all on 127.0.0.1 only. It logs to /var/log/pyo-desktop.log.
#
# The browser depends on the architecture, one per image: Google Chrome
# on amd64 (Google has no Linux arm64 build), Playwright's Chromium on
# arm64. Both run as /usr/local/bin/browser, also named google-chrome and
# chromium. /etc/pyo/browser says which one it is.
#
# Everything runs as root, like the rest of the sandbox, so the browser
# runs with --no-sandbox: the sandbox itself is the isolation.

ARG BASE=ghcr.io/upsetdev/pyo-sandbox-images/base:24.04
ARG NOVNC_VERSION=1.7.0
ARG NOVNC_SHA256=b1003a11b6e6e8d8f7f5e5586daae7f8ca651d8aee0aa155ff9ac841c48f52c6
ARG PLAYWRIGHT_VERSION=1.65.1

FROM ${BASE}
ARG NOVNC_VERSION NOVNC_SHA256 PLAYWRIGHT_VERSION
ARG TARGETARCH
LABEL org.opencontainers.image.source=https://github.com/upsetdev/pyo-sandbox-images \
      org.opencontainers.image.title="Pyo Sandbox desktop" \
      org.opencontainers.image.description="Pyo Sandbox base with a desktop, noVNC and a browser with CDP" \
      org.opencontainers.image.licenses=Apache-2.0 \
      dev.pyo.sandbox.contract="1"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# The screen, the window manager, the panel, a terminal and fonts. Droid
# Sans Fallback covers CJK at a fraction of Noto CJK's size.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      dbus-x11 fonts-dejavu-core fonts-droid-fallback fonts-liberation \
      fonts-noto-color-emoji openbox tigervnc-standalone-server tint2 \
      wmctrl x11-xserver-utils xdg-utils xdotool xfce4-terminal; \
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

# noVNC's web files, checked against their sha256. Ubuntu's package would
# bring Node.js and websockify along.
RUN set -eux; \
    curl -fsSLo /tmp/novnc.tar.gz "https://github.com/novnc/noVNC/archive/refs/tags/v$NOVNC_VERSION.tar.gz"; \
    echo "$NOVNC_SHA256  /tmp/novnc.tar.gz" | sha256sum -c -; \
    mkdir -p /usr/share/novnc; \
    tar -xzf /tmp/novnc.tar.gz -C /usr/share/novnc --strip-components=1 --no-same-owner; \
    rm /tmp/novnc.tar.gz; \
    # Its own tooling and tests only. Not vendor/pako/lib/utils, which the
    # page imports.
    cd /usr/share/novnc; \
    rm -rf docs tests snap utils po .github; \
    # noVNC at / as well as /vnc.html.
    ln -sf vnc.html index.html

COPY check-novnc.py /tmp/check-novnc.py
RUN python3 /tmp/check-novnc.py /usr/share/novnc && rm /tmp/check-novnc.py

COPY start /etc/pyo/start
COPY desktop.py /usr/local/lib/pyo-desktop/desktop.py
COPY session /usr/local/lib/pyo-desktop/session
COPY tint2rc /etc/xdg/tint2/tint2rc

RUN chmod 755 /etc/pyo/start /usr/local/lib/pyo-desktop/session \
    && python3 -m py_compile /usr/local/lib/pyo-desktop/desktop.py

WORKDIR /root
CMD ["bash"]

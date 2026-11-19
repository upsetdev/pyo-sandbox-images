# Pyo Sandbox image `base`: Ubuntu 24.04 LTS with the tools coding agents
# expect. Lean on purpose. The `desktop` image is built on it.
#
# Pyo's contract (see README.md, contract 1): pyo-envd runs every command
# as root in /root, with HOME=/root, LANG=C.UTF-8 and
# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin. It
# doesn't use the image's User, Env, WorkingDir or Cmd. So every tool here
# lives on that PATH and nothing relies on ENV.
#
# Versions are pinned below. Bumping one is a one-line change. Downloads
# are checked against the sha256 their project publishes beside them, and
# apt repositories against their signing key's fingerprint.

ARG UBUNTU=ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85
ARG NODE_VERSION=24.22.3
ARG COREPACK_VERSION=0.36.0
ARG PNPM_VERSION=12.21.0
ARG BUN_VERSION=1.4.4
ARG DENO_VERSION=2.9.8
ARG GH_VERSION=2.105.0
ARG DOCKER_VERSION=29.10.0
ARG BUILDX_VERSION=0.39.0
ARG COMPOSE_VERSION=5.7.1
ARG CLAUDE_CODE_VERSION=2.1.325
ARG CODEX_VERSION=0.169.0
ARG OPENCODE_VERSION=1.19.5

# uv and uvx: Astral's static binaries for each architecture.
FROM ${UV_IMAGE} AS uv

FROM ${UBUNTU}
ARG NODE_VERSION COREPACK_VERSION PNPM_VERSION BUN_VERSION DENO_VERSION \
    GH_VERSION DOCKER_VERSION BUILDX_VERSION COMPOSE_VERSION \
    CLAUDE_CODE_VERSION CODEX_VERSION OPENCODE_VERSION
ARG TARGETARCH
LABEL org.opencontainers.image.source=https://github.com/upsetdev/pyo-sandbox-images \
      org.opencontainers.image.title="Pyo Sandbox base" \
      org.opencontainers.image.description="Ubuntu 24.04 with git, Python, uv, Node.js, Bun, Deno, Docker CLI and coding agent CLIs" \
      org.opencontainers.image.licenses=Apache-2.0 \
      dev.pyo.sandbox.notices=/usr/share/doc/pyo-sandbox-images/THIRD_PARTY_NOTICES.md \
      dev.pyo.sandbox.contract="1"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# Ubuntu's packages. The ubuntu image is already minimized: dpkg leaves
# out man pages and docs. Weekly builds pick up security updates.
RUN set -eux; \
    apt-get update; \
    apt-get -y upgrade; \
    apt-get install -y --no-install-recommends \
      bash-completion build-essential ca-certificates cmake curl dnsutils \
      file git gnupg iproute2 iputils-ping jq less locales lsof nano \
      netcat-openbsd ninja-build openssh-client pkg-config procps \
      python-is-python3 python3 python3-dev python3-pip python3-venv \
      ripgrep rsync sudo tzdata unzip vim-tiny wget xz-utils zip; \
    # C.UTF-8 is built in. en_US.UTF-8 too, for tools that ask for it.
    sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen; \
    locale-gen; \
    # A sandbox is thrown away: let pip install for the system Python,
    # as agents expect.
    rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED; \
    ln -s /usr/bin/vim.tiny /usr/local/bin/vim; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

# Docker's CLI with buildx and compose, from Docker's apt repository.
# Only the CLI: there's no Docker daemon in the image.
RUN set -eux; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/key; \
    gpg --show-keys --with-colons /tmp/key | grep -q '^fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:' \
      || { echo "Docker's key isn't 9DC858229FC7DD38854AE2D88D81803C0EBFCD88" >&2; exit 1; }; \
    install -d -m 0755 /etc/apt/keyrings; \
    gpg --dearmor < /tmp/key > /etc/apt/keyrings/docker.gpg; \
    rm /tmp/key; \
    echo "deb [arch=$TARGETARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      "docker-ce-cli=5:$DOCKER_VERSION-1~ubuntu.24.04~noble" \
      "docker-buildx-plugin=$BUILDX_VERSION-1~ubuntu.24.04~noble" \
      "docker-compose-plugin=$COMPOSE_VERSION-1~ubuntu.24.04~noble"; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb; \
    docker --version; docker buildx version; docker compose version

# GitHub CLI, the .deb from its GitHub release. GitHub's apt repository
# drops old versions, which breaks a pinned build.
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64|arm64) f="gh_${GH_VERSION}_linux_$TARGETARCH.deb" ;; \
      *) echo "No gh for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -fsSLO "https://github.com/cli/cli/releases/download/v$GH_VERSION/$f"; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_checksums.txt" | grep " $f\$" | sha256sum -c -; \
    dpkg -i "$f"; \
    rm "$f"; \
    gh --version

# Node.js LTS, the official build, then pnpm through corepack. pnpm is
# fetched now, so it works in a sandbox without network too.
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) arch=x64 ;; arm64) arch=arm64 ;; \
      *) echo "No Node.js for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    f="node-v$NODE_VERSION-linux-$arch.tar.xz"; \
    cd /tmp; \
    curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/$f"; \
    curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" | grep " $f\$" | sha256sum -c -; \
    tar -xJf "$f" -C /usr/local --strip-components=1 --no-same-owner \
      --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/doc' \
      --exclude='*/include/node/openssl/archs'; \
    rm "$f"; \
    # Its license, with those of what it bundles, where docs go.
    install -d /usr/share/doc/nodejs; \
    mv /usr/local/LICENSE /usr/share/doc/nodejs/LICENSE; \
    npm install -g "corepack@$COREPACK_VERSION"; \
    corepack enable pnpm; \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack install -g "pnpm@$PNPM_VERSION"; \
    npm cache clean --force; \
    rm -rf /tmp/* /root/.npm; \
    node --version; npm --version; pnpm --version

# Bun and Deno, their official builds.
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) bun=bun-linux-x64; deno=deno-x86_64-unknown-linux-gnu ;; \
      arm64) bun=bun-linux-aarch64; deno=deno-aarch64-unknown-linux-gnu ;; \
      *) echo "No Bun or Deno for $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    cd /tmp; \
    curl -fsSLO "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/$bun.zip"; \
    curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/SHASUMS256.txt" | grep " $bun.zip\$" | sha256sum -c -; \
    unzip -q "$bun.zip"; \
    install -m 0755 "$bun/bun" /usr/local/bin/bun; \
    ln -s bun /usr/local/bin/bunx; \
    curl -fsSLO "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/$deno.zip"; \
    curl -fsSL "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/$deno.zip.sha256sum" | sha256sum -c -; \
    unzip -q "$deno.zip" -d /usr/local/bin; \
    chmod 0755 /usr/local/bin/deno; \
    rm -rf /tmp/*; \
    bun --version; deno --version

COPY --from=uv /uv /uvx /usr/local/bin/

# Coding agents' CLIs, from npm.
RUN set -eux; \
    npm install -g \
      "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION" \
      "@openai/codex@$CODEX_VERSION" \
      "opencode-ai@$OPENCODE_VERSION"; \
    # opencode's install copies the build it picked to its bin. It also
    # leaves a second build (baseline) it doesn't use: about 200 MB.
    cd /usr/local/lib/node_modules/opencode-ai; \
    for d in node_modules/opencode-*; do \
      [ bin/opencode.exe -ef "$d/bin/opencode" ] || rm -rf "$d"; \
    done; \
    cd /; \
    npm cache clean --force; \
    rm -rf /tmp/* /root/.npm; \
    claude --version; codex --version; opencode --version

RUN uv --version && python3 --version && git --version

# Third-party software in the image and its licenses. The build needs the
# repo's root as the named context `notices`: --build-context notices=.
COPY --from=notices THIRD_PARTY_NOTICES.md /usr/share/doc/pyo-sandbox-images/THIRD_PARTY_NOTICES.md

WORKDIR /root
CMD ["bash"]

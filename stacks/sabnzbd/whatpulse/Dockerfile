# The WhatPulse Linux client and the packet capture service it needs, in one
# image. Both halves ship as prebuilt downloads pinned by checksum, the same
# shape the tqm rider already uses: there is no registry image for either, and
# the client exists only as an AppImage (issue #1582).
#
# The two live together because the capture service forwards packets to the
# client over an unauthenticated TCP socket, so the only safe listener is one on
# the client's own loopback (issue #1579).

# Extraction stage. The AppImage is a self-mounting squashfs and needs FUSE to
# run as a file, which a container does not have, so it is unpacked here and the
# resulting tree is copied into the runtime stage as plain files.
FROM debian:bookworm-slim AS appimage

# Upstream publishes the client under a single "latest" URL - there is no
# versioned path, every one tried returns 404 - so the checksum is the pin. A
# new release changes it and this build fails loudly rather than silently
# shipping something else; bump both lines together after checking the release
# notes. WHATPULSE_VERSION is what the pinned file reports about itself and is
# carried for the label alone.
ARG WHATPULSE_VERSION=6.3.2
ARG WHATPULSE_SHA256=fd7005aa2243d4d22d68590a43203efa10926fff7d52d50c96d0050a5bf3aa64

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/whatpulse.AppImage \
    "https://releases.whatpulse.org/latest/linux/whatpulse-linux-latest_amd64.AppImage" \
    && echo "${WHATPULSE_SHA256}  /tmp/whatpulse.AppImage" | sha256sum -c - \
    && chmod +x /tmp/whatpulse.AppImage \
    && cd /tmp && /tmp/whatpulse.AppImage --appimage-extract >/dev/null \
    && rm /tmp/whatpulse.AppImage

# Capture service. Upstream ships a release binary next to its sources, so it is
# taken as it is rather than compiled: the published SHA256SUMS is the same
# checksum gate the Makefile route would need anyway, and the build stays a
# download instead of a toolchain.
FROM debian:bookworm-slim AS pcap

ARG PCAP_SERVICE_VERSION=1.5.1
ARG PCAP_SERVICE_SHA256=5f515155618df6c2ab5a4aba2a5188f2f55c33d852babdc732b709974f6294a5

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/whatpulse-pcap-service \
    "https://github.com/whatpulse/linux-external-pcap-service/releases/download/v${PCAP_SERVICE_VERSION}/whatpulse-pcap-service-${PCAP_SERVICE_VERSION}-linux-amd64" \
    && echo "${PCAP_SERVICE_SHA256}  /tmp/whatpulse-pcap-service" | sha256sum -c - \
    && chmod +x /tmp/whatpulse-pcap-service

FROM debian:bookworm-slim

# The Unraid icon for every container built from this image - the host-namespace
# client and both namespace riders. A container inherits its image's labels, so
# this is the single place to bump it and the compose files carry no icon label
# of their own.
LABEL net.unraid.docker.icon=https://img.ptscreens.com/whatpulse.png

# Debian rather than the alpine every other locally built image here uses: the
# client is a Qt AppImage built against glibc and does not run on musl.
#
# The package set is exactly what the extracted tree asks for - it was derived by
# resolving every bundled library of the client against an empty base until
# nothing reported "not found", not guessed from a list of usual suspects.
# xvfb/x11vnc/novnc are the virtual display and its web front end, which is how
# the one-time browser login and any later look at the client happen on a server
# with no desktop. openbox and trayer are not decoration: the client starts
# minimised into the system tray and quits on the spot, status 0 and nothing
# logged, when there is no tray to dock into. dbus-x11 gives it the session bus
# it expects. libpcap0.8 is the capture service's only runtime dependency.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
        fonts-dejavu-core \
        libpcap0.8 \
        libegl1 \
        libgl1 \
        libx11-6 \
        libfontconfig1 \
        libfreetype6 \
        libglib2.0-0 \
        libkrb5-3 \
        libdbus-1-3 \
        libxkbcommon0 \
        libxkbcommon-x11-0 \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-xinerama0 \
        xvfb \
        xauth \
        x11-utils \
        x11vnc \
        novnc \
        websockify \
        openbox \
        trayer \
        dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=appimage /tmp/squashfs-root /opt/whatpulse
COPY --from=pcap /tmp/whatpulse-pcap-service /usr/local/bin/whatpulse-pcap-service

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The client keeps its settings, its local statistics database and its logs under
# $HOME/.local/share, in two directories that differ only in case - "whatpulse"
# and "WhatPulse" - so the share directory itself is the persistent volume rather
# than either of them. Without it the linked computer is lost on every recreate
# and has to be logged in and linked again by hand.
RUN useradd --create-home --uid 1000 --shell /usr/sbin/nologin whatpulse \
    && mkdir -p /home/whatpulse/.local/share \
    && chown -R whatpulse:whatpulse /home/whatpulse

ENV HOME=/home/whatpulse \
    LANG=C.UTF-8 \
    QT_QPA_PLATFORM=xcb \
    DISPLAY=:1 \
    WP_SCREEN=1280x800x24 \
    WP_VNC_PORT=5999 \
    WP_WEB_PORT=6799 \
    WP_INTERFACE=br0

# Deliberately root: the capture service tests for uid 0 itself and refuses to
# capture otherwise, so a file capability cannot replace it. The entrypoint drops
# everything else to the whatpulse user.
WORKDIR /home/whatpulse

# Marker only: it changes when the build context changes, so the deploy that
# rebuilds this image is triggered by a moved compose.yaml (see issue #935).
ARG SRC_REV

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# WhatPulse

> Counts the server's own network traffic into the WhatPulse account, alongside the desktops

## Stack Role

This stack directory stores the `compose.yaml`, `README.md`, and tracked `.env.example` for `whatpulse`.

## Services

- `whatpulse`

## Shape

The stack is one container holding both halves the Linux client needs: the client itself, an AppImage unpacked at build time, and the separate packet capture service that feeds it. They live together because the capture forwards packets over an unauthenticated TCP socket, so the only safe listener is one on the client's own loopback.

Three properties of the deployment are not cosmetic:

- **Host network namespace.** The capture has to see the frames crossing `br0`; a bridged container sees only its own veth. It also puts capture and client on the same loopback.
- **`NET_RAW` and `NET_ADMIN`, running as root.** The capture service tests for uid 0 itself and refuses otherwise, so a file capability cannot replace either.
- **A seccomp profile that fails one syscall.** The capture service prefers a global `AF_PACKET` ring bound to every interface and honours `-i` only on its libpcap fallback. Unpinned it would count `br0`, `eth0` - which carry the same frames - and around forty `veth` pairs, several times per byte. `seccomp-no-packet-ring.json` fails `setsockopt(SOL_PACKET, PACKET_RX_RING)` and nothing else, which sends the service down the per-interface path. The rule also matches on the option length, because libpcap builds its own ring through the very same syscall: the global ring passes a 16-byte `struct tpacket_req`, libpcap a 28-byte `struct tpacket_req3`, and a rule without that third condition blocks both paths and captures nothing at all.

## The web front end, and why it stays internal

The front end is published as `wp.example.com` on the `websecure-internal` entrypoint and nowhere else. The bare host redirects to `/vnc.html`, the noVNC client itself, rather than the directory index the front end answers with at the root; the redirect matches the root alone, so the assets that page pulls afterwards resolve normally. It is a noVNC canvas onto a logged-in desktop session, guarded by `WP_VNC_PASSWORD` and nothing else, and neither internal chain carries authentication, so an external router would put a remote desktop on the internet behind a single password. What actually keeps it off the internet is the absence of a port forward to the internal entrypoint, not the router definition; the router only makes sure Traefik never offers it on the external one.

The labels are ordinary stack labels despite the host network namespace: every stack here names its upstream through `loadbalancer.server.url` rather than letting the Docker provider detect a container port, so the only difference is that the URL is the host address instead of a service name, and the `traefik.docker.network` hint the bridged stacks carry is left out.

## One-time login

The account is linked through the web VNC front end, and it is a manual step: nothing in the compose file can do it, and traffic is counted only once a computer is linked.

1. Open [https://wp.example.com](https://wp.example.com) - or `http://192.0.2.99:6799` directly - and connect with the password from `WP_VNC_PASSWORD`.
2. In the client, log in to the WhatPulse account through the dialog it offers.
3. Link this machine as the computer `homelab-host`, alongside the existing `smooPC` and `smooBookPro`.

The linked identity lives in `/mnt/user/appdata/whatpulse` and survives a recreate, so this is done once rather than per deploy.

## Verifying the capture

- The service log shows `Failed to set PACKET_RX_RING` followed by the per-interface PCap path. That line is the profile working, not an error.
- The client's Network tab lists `br0` alone, with no `veth*` or `br-*` rows.
- A deliberate download on the host produces a matching increase in the `homelab-host` numbers on whatpulse.org.

## Upstream

- Website: [https://whatpulse.org/](https://whatpulse.org/)
- GitHub: [https://github.com/whatpulse/linux-external-pcap-service](https://github.com/whatpulse/linux-external-pcap-service)

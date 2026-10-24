# nzbfast 1.1.5 plus the tools the sabnzbd post-processing scripts need (#5158).
#
# The published image is Debian bookworm with curl, bash and p7zip only.
# extract_iso.sh is fine with that (7z is present), but the staging script needs jq,
# python3 with PyYAML (tuning read, shape_payload.py, the rhd dispatcher) and a
# wget for notifications. The scripts stay unchanged; only the tools are added.
# Built by Komodo like repollo:local in the sabnzbd stack.
FROM nzbfast/nzbfast:1.8.0@sha256:e8ac3613b858544197114f691e3ae83828e82c0eed150d92f6219b63690e0612

# The SRC_REV marker in compose.yaml moves with this context (issue #935).
ARG SRC_REV=unset

RUN apt-get update \
    && apt-get install -y --no-install-recommends jq python3 python3-yaml wget \
    && rm -rf /var/lib/apt/lists/*

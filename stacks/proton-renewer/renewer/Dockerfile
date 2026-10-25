FROM golang:1.27-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS build

# Upstream confgen at a pinned commit. It takes the password on stdin (`--password-stdin`). One local patch: the renewal response is decoded into a strictly typed feature struct that Proton's answer for an older profile does not fit (live 2026-10-18: HTTP 200, Code 1000, renewal done server side, yet "unexpected response" client side). The struct is never read, so VPNInfo.Features takes the loose map type the list endpoint already uses. Drop the sed once upstream decodes this loosely.
ARG CONFGEN_REV=9c01086cc41fbc425087a9d78f7e2d745206cfe8
RUN apk add --no-cache git \
    && git clone https://github.com/hatemosphere/protonvpn-wg-confgen.git /src \
    && git -C /src checkout "$CONFGEN_REV" \
    && sed -i 's/^\(\tFeatures *\)CertFeatures\( *`json:"Features"`\)/\1CertFeaturesSent\2/' /src/internal/api/types.go \
    && grep -q 'CertFeaturesSent *`json:"Features"`' /src/internal/api/types.go \
    && cd /src && CGO_ENABLED=0 go build -trimpath -o /protonvpn-wg ./cmd/protonvpn-wg

FROM alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

# jq parses the config list, wget (busybox) posts the Apprise alert. ca-certificates for the Proton API.
RUN apk add --no-cache jq ca-certificates tzdata

COPY --from=build /protonvpn-wg /usr/local/bin/protonvpn-wg
COPY renewer.sh /usr/local/bin/renewer.sh

# Marker only: it changes when the build context changes, so the content of this image is recorded in compose.yaml (see docs/image-pinning.md).
ARG SRC_REV

# The confgen session file lives under $HOME, so $HOME is the volume.
ENV HOME=/data
WORKDIR /data
CMD ["sh", "/usr/local/bin/renewer.sh"]

FROM golang:1.27-alpine@sha256:dbaa054703263d06c8b49576667418473b6231f8c0fa69dee103207fdb8e3654 AS build

# Upstream confgen at a pinned commit. It takes the password on stdin (`--password-stdin`). One local patch: the renewal response is decoded into a strictly typed feature struct that Proton's answer for an older profile does not fit (live 2026-10-18: HTTP 200, Code 1000, renewal done server side, yet "unexpected response" client side). The struct is never read, so VPNInfo.Features takes the loose map type the list endpoint already uses. Drop the sed once upstream decodes this loosely.
ARG CONFGEN_REV=9c01086cc41fbc425087a9d78f7e2d745206cfe8
RUN apk add --no-cache git \
    && git clone https://github.com/hatemosphere/protonvpn-wg-confgen.git /src \
    && git -C /src checkout "$CONFGEN_REV" \
    && sed -i 's/^\(\tFeatures *\)CertFeatures\( *`json:"Features"`\)/\1CertFeaturesSent\2/' /src/internal/api/types.go \
    && grep -q 'CertFeaturesSent *`json:"Features"`' /src/internal/api/types.go \
    && cd /src && CGO_ENABLED=0 go build -trimpath -o /protonvpn-wg ./cmd/protonvpn-wg

FROM alpine:3.24@sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a

# jq parses the config list, wget (busybox) posts the Apprise alert. ca-certificates for the Proton API.
RUN apk add --no-cache jq ca-certificates tzdata

COPY --from=build /protonvpn-wg /usr/local/bin/protonvpn-wg
COPY renewer.sh /usr/local/bin/renewer.sh

# The confgen session file lives under $HOME, so $HOME is the volume.
ENV HOME=/data
WORKDIR /data
CMD ["sh", "/usr/local/bin/renewer.sh"]

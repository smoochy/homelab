FROM python:3.14-alpine@sha256:f6a589d43c42b9e7f7dc67a12d37132491f362859a5d750607710cc56da3bc72

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

# Marker only: it changes when the build context changes, so the content of this
# image is recorded in compose.yaml (see docs/image-pinning.md). Unlike the
# qbittorrent riders this stack is not Komodo-deployed, so the marker is a
# content record rather than a deploy trigger.
ARG SRC_REV

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

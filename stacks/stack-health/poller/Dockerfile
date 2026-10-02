FROM python:3.14-alpine@sha256:c6ead215bfd31f1e433d968853b7a769989117115b728874824e6c0a27cb96fc

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

# Marker only: it changes when the build context changes, so the content of this
# image is recorded in compose.yaml (see docs/image-pinning.md). Unlike the
# qbittorrent riders this stack is not Komodo-deployed, so the marker is a
# content record rather than a deploy trigger.
ARG SRC_REV

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

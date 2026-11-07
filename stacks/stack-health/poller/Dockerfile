FROM python:3.14-alpine@sha256:b15fd707501f872b2d46a8edacb18aca52db393460d17a60a20e7231dbdb3263

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

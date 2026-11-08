FROM python:3.14-alpine@sha256:a18b20ad69e74df6cf6d2e1b1a260d7a1ecf5380fd83b310f83ba88c461cf894

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

FROM python:3.14-alpine@sha256:eb2c62658b8d51bff0acc408504b76521d02030de56a8a3c1e830083e89b89d2

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

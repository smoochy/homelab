FROM python:3.14-alpine@sha256:5862d971d1f0ae26b258cefa4e893556b1d3aba81bd2ff30888704ad378bab67

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

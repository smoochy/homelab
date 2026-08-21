FROM python:3.14-alpine

RUN pip install --no-cache-dir requests==2.32.3

COPY stack_health.py /app/stack_health.py

WORKDIR /app
CMD ["python", "-u", "/app/stack_health.py"]

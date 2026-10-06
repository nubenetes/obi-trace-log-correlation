FROM python:3.12-alpine
WORKDIR /app

# CRITICAL for OBI Trace-Log Correlation:
# Python stdout/stderr must be unbuffered so writes are made directly to the fd
# by the thread executing the request, allowing eBPF to capture active trace context.
ENV PYTHONUNBUFFERED=1

COPY app.py .
EXPOSE 8082
USER 10001:10001
CMD ["python", "app.py"]

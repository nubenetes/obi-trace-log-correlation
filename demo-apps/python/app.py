import json
import logging
import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

# Note: Python stdout MUST be unbuffered (PYTHONUNBUFFERED=1)
# so the write syscall happens synchronously on the request-handling thread!
class JSONLogFormatter(logging.Formatter):
    def format(self, record):
        log_payload = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "process": record.process,
            "thread": record.threadName,
        }
        if hasattr(record, "extra_data"):
            log_payload.update(record.extra_data)
        return json.dumps(log_payload)

logger = logging.getLogger("python-service")
logger.setLevel(logging.INFO)
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JSONLogFormatter())
logger.addHandler(handler)

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK\n")
            return

        if self.path == "/compute":
            # OBI eBPF captures the HTTP request and injects trace_id and span_id into this stdout write!
            logger.info("processing compute payload in python runtime", extra={"extra_data": {
                "route": "/compute",
                "client": self.client_address[0],
                "operation": "vector_product"
            }})

            time.sleep(0.02)  # Simulate compute work
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok","runtime":"python-unbuffered","result":42}\n')
            return

        self.send_response(404)
        self.end_headers()

def run():
    port = int(os.environ.get("PORT", "8082"))
    server_address = ("", port)
    httpd = HTTPServer(server_address, RequestHandler)
    logger.info(f"Python unbuffered service listening on port {port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Python service stopped")

if __name__ == "__main__":
    run()

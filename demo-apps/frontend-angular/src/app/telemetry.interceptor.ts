import { HttpInterceptorFn, HttpRequest, HttpHandlerFn } from '@angular/common/http';

/**
 * OpenTelemetry W3C Trace Context HTTP Interceptor for Angular 17+
 * 
 * In a Single Page Application (SPA), browser console logs run outside the host Linux kernel.
 * To achieve end-to-end distributed correlation with OBI eBPF on backend microservices:
 * 1. The frontend initiates a client span or generates a W3C traceparent header.
 * 2. This interceptor injects the 'traceparent' header into all outgoing backend API requests.
 * 3. When the request lands on a Linux node, OBI's socket probe extracts the header and
 *    binds the Trace ID into the kernel BPF map for backend stdout log correlation.
 */
export const openTelemetryInterceptor: HttpInterceptorFn = (req: HttpRequest<unknown>, next: HttpHandlerFn) => {
  // If request already has traceparent, pass through
  if (req.headers.has('traceparent')) {
    return next(req);
  }

  // Generate 16-byte TraceId and 8-byte SpanId (simulating OpenTelemetry Web SDK trace context)
  const traceId = generateHex(16);
  const spanId = generateHex(8);
  const traceFlags = '01'; // Sampled

  // W3C Trace Context standard format: 00-{traceId}-{spanId}-{flags}
  const traceparent = `00-${traceId}-${spanId}-${traceFlags}`;

  const tracedReq = req.clone({
    setHeaders: {
      traceparent,
      'baggage': `frontend.app=angular-spa,frontend.version=17.2`
    }
  });

  return next(tracedReq);
};

function generateHex(byteLength: number): string {
  const bytes = new Uint8Array(byteLength);
  if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
    crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < byteLength; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
  }
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

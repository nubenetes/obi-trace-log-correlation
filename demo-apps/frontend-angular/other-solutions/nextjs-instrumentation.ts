/**
 * Next.js 14/15 App Router: Distributed Tracing & W3C Trace Context Propagation
 * 
 * Demonstrates:
 * 1. Server Components (RSC) running on Node.js on Linux (where OBI intercepts stdout writes).
 * 2. Client Components ('use client') injecting W3C traceparent into fetch() calls to backends.
 */

// 1. Client-Side Traced Fetch Wrapper (for React / Next.js Client Components)
export async function tracedFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const headers = new Headers(init?.headers);

  // If traceparent header is not present, generate standard W3C Trace Context
  if (!headers.has('traceparent')) {
    const traceId = Array.from(crypto.getRandomValues(new Uint8Array(16)))
      .map(b => b.toString(16).padStart(2, '0')).join('');
    const spanId = Array.from(crypto.getRandomValues(new Uint8Array(8)))
      .map(b => b.toString(16).padStart(2, '0')).join('');
    
    // Format: 00-{trace_id}-{span_id}-01
    headers.set('traceparent', `00-${traceId}-${spanId}-01`);
    headers.set('baggage', 'client.framework=nextjs-app-router,client.runtime=react18');
  }

  return fetch(input, {
    ...init,
    headers,
  });
}

// 2. Next.js Server-Side Instrumentation (instrumentation.ts)
// Runs on Node.js server startup before handling SSR / Server Actions.
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    // In Node.js runtime, standard console.log / stdout writes trigger write() syscalls
    // that OBI eBPF intercepts and enriches with trace context.
    console.log(JSON.stringify({
      level: 'INFO',
      msg: 'Next.js Node.js runtime initialized for OBI eBPF correlation',
      node_version: process.version,
      pid: process.pid
    }));
  }
}

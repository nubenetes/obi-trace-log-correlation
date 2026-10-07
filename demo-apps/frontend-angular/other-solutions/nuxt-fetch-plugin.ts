/**
 * Nuxt 3 / Vue 3 Plugin: W3C Trace Context HTTP Propagation
 * 
 * Nuxt 3 uses Nitro as its server engine (running on Node.js) and ofetch ($fetch) for HTTP requests.
 * This plugin automatically intercepts all client-side and server-side $fetch calls,
 * injecting the W3C 'traceparent' header into outgoing backend API requests.
 */

export default defineNuxtPlugin(() => {
  const generateHex = (bytes: number): string => {
    const arr = new Uint8Array(bytes);
    if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
      crypto.getRandomValues(arr);
    } else {
      for (let i = 0; i < bytes; i++) arr[i] = Math.floor(Math.random() * 256);
    }
    return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('');
  };

  // Global ofetch hook intercepting outgoing API requests
  globalThis.$fetch = $fetch.create({
    onRequest({ request, options }) {
      options.headers = options.headers || {};
      const headers = new Headers(options.headers);

      if (!headers.has('traceparent')) {
        const traceId = generateHex(16);
        const spanId = generateHex(8);
        const traceparent = `00-${traceId}-${spanId}-01`;

        headers.set('traceparent', traceparent);
        headers.set('baggage', 'frontend.framework=nuxt3-vue3');
        options.headers = headers;
      }
    },
    onResponseError({ response }) {
      // Forward client errors to telemetry endpoint
      if (process.client) {
        $fetch('/api/telemetry/logs', {
          method: 'POST',
          body: {
            error: response.statusText,
            status: response.status,
            timestamp: new Date().toISOString()
          }
        }).catch(() => {});
      }
    }
  });
});

// Type stub for standalone compilation
declare function defineNuxtPlugin(plugin: (nuxtApp?: unknown) => void): unknown;
declare const $fetch: { create: (opts: unknown) => unknown };

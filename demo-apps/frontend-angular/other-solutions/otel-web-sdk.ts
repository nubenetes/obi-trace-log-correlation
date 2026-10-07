/**
 * OpenTelemetry Official Web SDK Browser Setup
 * 
 * Demonstrates production-grade client-side tracing using official OpenTelemetry packages:
 * - @opentelemetry/sdk-trace-web
 * - @opentelemetry/instrumentation-fetch
 * - @opentelemetry/instrumentation-xml-http-request
 * - @opentelemetry/exporter-trace-otlp-http
 */

import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { XMLHttpRequestInstrumentation } from '@opentelemetry/instrumentation-xml-http-request';
import { Resource } from '@opentelemetry/resources';
import { SEMRESATTRS_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

export function initializeBrowserOpenTelemetry(serviceName: string, collectorUrl: string) {
  // 1. Initialize Tracer Provider with Resource attributes
  const provider = new WebTracerProvider({
    resource: new Resource({
      [SEMRESATTRS_SERVICE_NAME]: serviceName,
    }),
  });

  // 2. Configure OTLP HTTP Exporter to send traces to OTel Collector or Gateway
  const exporter = new OTLPTraceExporter({
    url: `${collectorUrl}/v1/traces`,
  });

  provider.addSpanProcessor(new BatchSpanProcessor(exporter));

  // 3. Register Context Manager (ZoneContextManager for Angular / AsyncLocalStorage for Node)
  provider.register({
    contextManager: new ZoneContextManager(),
  });

  // 4. Auto-instrument Fetch and XMLHttpRequest
  // Injects W3C 'traceparent' header into all outgoing requests targeting matching URLs
  registerInstrumentations({
    instrumentations: [
      new FetchInstrumentation({
        propagateTraceHeaderCorsUrls: [
          new RegExp('.*'), // Injects traceparent on all API endpoints
        ],
        clearTimingResources: true,
      }),
      new XMLHttpRequestInstrumentation({
        propagateTraceHeaderCorsUrls: [
          new RegExp('.*'),
        ],
      }),
    ],
  });

  return provider.getTracer(serviceName);
}

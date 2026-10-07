import { Component, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';

/**
 * Angular Root Component demonstrating client actions and telemetry forwarding.
 */
@Component({
  selector: 'app-root',
  standalone: true,
  template: `
    <div class="checkout-container">
      <h2>Angular SPA Client Telemetry & OBI Correlation Demo</h2>
      <p>Clicking "Submit Order" initiates an HTTP request intercepted by <code>openTelemetryInterceptor</code>.</p>
      <button (click)="submitOrder()">Submit Order</button>
      <div *ngIf="statusMessage" class="status-box">
        <pre>{{ statusMessage }}</pre>
      </div>
    </div>
  `,
  styles: [`
    .checkout-container { padding: 1.5rem; font-family: sans-serif; background: #1e293b; color: #f8fafc; border-radius: 8px; }
    button { background: #3b82f6; color: white; padding: 0.6rem 1.2rem; border: none; border-radius: 4px; cursor: pointer; }
    .status-box { margin-top: 1rem; background: #020617; padding: 1rem; border-radius: 4px; color: #38bdf8; }
  `]
})
export class AppComponent {
  private http = inject(HttpClient);
  statusMessage = '';

  submitOrder() {
    this.statusMessage = 'Submitting order with W3C traceparent header...';

    // Outgoing HTTP request will automatically have 'traceparent' attached by openTelemetryInterceptor
    this.http.post<{ status: string; orderId: string }>('/api/orders', {
      sku: 'SKU-CLOUD-99',
      quantity: 1
    }).subscribe({
      next: (response) => {
        this.statusMessage = `Order Confirmed: ${response.orderId} (Status: ${response.status})\nCheck backend stdout logs for OBI zero-code trace enrichment!`;
      },
      error: (err) => {
        this.statusMessage = `Error placing order: ${err.message}`;
      }
    });
  }
}

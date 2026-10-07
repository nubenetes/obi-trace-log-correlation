import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

/**
 * Java Demo Application for OpenTelemetry eBPF (OBI) Zero-Code Trace-Log Correlation.
 * 
 * Demonstrates:
 * 1. Out-of-the-box working correlation on standard Platform Thread Pools (HttpServer default).
 * 2. Why Java 21 Project Loom Virtual Threads fail with carrier OS thread collisions in eBPF.
 */
public class App {

    // Log structured JSON synchronously to System.out
    private static void logJSON(String level, String message, String extra) {
        String threadName = Thread.currentThread().getName();
        long threadId = Thread.currentThread().threadId();
        boolean isVirtual = Thread.currentThread().isVirtual();

        // OBI intercepts this System.out.println -> write() syscall on stdout.
        // - Platform Threads: ByteBuddy + ioctl links worker thread to HTTP trace in traces_ctx_v1.
        // - Virtual Threads: Carrier OS thread multiplexing causes trace cross-contamination.
        String logEntry = String.format(
            "{\"timestamp\":\"%s\",\"level\":\"%s\",\"msg\":\"%s\",\"thread\":\"%s\",\"thread_id\":%d,\"is_virtual\":%b%s}\n",
            Instant.now().toString(),
            level,
            message,
            threadName,
            threadId,
            isVirtual,
            (extra != null && !extra.isEmpty() ? "," + extra : "")
        );
        System.out.print(logEntry);
        System.out.flush();
    }

    public static void main(String[] args) throws IOException {
        int port = 8085;
        String portEnv = System.getenv("PORT");
        if (portEnv != null && !portEnv.isEmpty()) {
            try {
                port = Integer.parseInt(portEnv);
            } catch (NumberFormatException ignored) {}
        }

        boolean useVirtualThreads = "true".equalsIgnoreCase(System.getenv("USE_VIRTUAL_THREADS"));

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        ExecutorService executor;
        if (useVirtualThreads) {
            // ⚠️ PROJECT LOOM VIRTUAL THREADS (Java 21+)
            // FAILS with OBI: Multiple virtual threads multiplex over carrier OS threads.
            // bpf_get_current_pid_tgid() only sees the carrier OS thread, causing trace context collision.
            executor = Executors.newVirtualThreadPerTaskExecutor();
            logJSON("WARN", "Server started using Project Loom VIRTUAL THREADS (OBI correlation will collide across carrier threads)", "\"warning\":\"virtual_threads_active\"");
        } else {
            // ✅ PLATFORM THREAD POOL (Standard Enterprise Java)
            // WORKS with OBI: ByteBuddy + ioctl hierarchy links worker threads to parent request traces.
            executor = Executors.newFixedThreadPool(20);
            logJSON("INFO", "Server started using standard PLATFORM THREAD POOL (Fully compatible with OBI zero-code)", "\"mode\":\"platform_threads\"");
        }

        server.setExecutor(executor);

        // Health check endpoint
        server.createContext("/healthz", exchange -> {
            byte[] response = "OK\n".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, response.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(response);
            }
        });

        // Payment / Business transaction endpoint
        server.createContext("/payments", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String method = exchange.getRequestMethod();

            // Intercepted by OBI: Automatically enriches this stdout write with trace_id and span_id!
            logJSON("INFO", "processing incoming payment transaction", 
                String.format("\"path\":\"%s\",\"method\":\"%s\",\"status\":\"authorized\",\"amount\":149.99", path, method)
            );

            byte[] response = "{\"status\":\"authorized\",\"platform\":\"java-21\"}\n".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, response.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(response);
            }
        });

        server.start();
        logJSON("INFO", "Java microservice listening on port " + port, "");
    }
}

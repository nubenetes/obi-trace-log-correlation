package main

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	// Standard JSON structured logger writing to stdout
	// Notice: ZERO OpenTelemetry SDK code or dependencies!
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	backendURL := os.Getenv("BACKEND_URL")
	if backendURL == "" {
		backendURL = "http://backend:8081"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK\n"))
	})

	mux.HandleFunc("/checkout", func(w http.ResponseWriter, r *http.Request) {
		orderID := fmt.Sprintf("ord-%d", time.Now().UnixNano()%100000)
		amount := 42.50

		// Plain application log - OBI eBPF will automatically inject trace_id and span_id!
		logger.Info("payment authorized",
			slog.String("order_id", orderID),
			slog.Float64("amount", amount),
			slog.String("currency", "USD"),
		)

		// Downstream call to backend: OBI propagates trace context in HTTP headers automatically!
		req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, backendURL+"/hello", nil)
		if err != nil {
			logger.Error("failed to construct backend request", slog.String("error", err.Error()))
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			logger.Error("downstream backend call failed",
				slog.String("order_id", orderID),
				slog.String("target_url", backendURL+"/hello"),
				slog.String("error", err.Error()),
			)
			http.Error(w, "backend service unavailable", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			logger.Error("failed reading backend response body", slog.String("error", err.Error()))
			http.Error(w, "read error", http.StatusInternalServerError)
			return
		}

		logger.Info("order processed successfully",
			slog.String("order_id", orderID),
			slog.Int("backend_status", resp.StatusCode),
		)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"completed","order_id":"%s","backend_response":"%s"}`+"\n", orderID, string(body))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	go func() {
		logger.Info("frontend service starting", slog.String("addr", server.Addr), slog.String("backend_url", backendURL))
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("frontend server failed", slog.String("error", err.Error()))
			os.Exit(1)
		}
	}()

	<-stop
	logger.Info("frontend service shutting down gracefully")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("forced shutdown error", slog.String("error", err.Error()))
	}
}

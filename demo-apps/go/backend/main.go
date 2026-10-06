package main

import (
	"context"
	"fmt"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	// Standard JSON structured logger writing to stdout
	// No SDK, no OTel imports
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK\n"))
	})

	mux.HandleFunc("/hello", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		// Simulate database lookup / business latency
		workDuration := time.Duration(15+rand.Intn(35)) * time.Millisecond
		time.Sleep(workDuration)

		// OBI automatically captures incoming traceparent, joins the trace, and decorates this log!
		logger.Info("handling request in backend",
			slog.String("path", r.URL.Path),
			slog.String("client_ip", r.RemoteAddr),
			slog.Duration("db_query_latency", workDuration),
			slog.Int("items_retrieved", 7),
		)

		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "hello from backend service (processed in %v)\n", time.Since(start))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
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
		logger.Info("backend service listening", slog.String("addr", server.Addr))
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("backend server error", slog.String("error", err.Error()))
			os.Exit(1)
		}
	}()

	<-stop
	logger.Info("backend service stopping gracefully")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		logger.Error("forced shutdown error", slog.String("error", err.Error()))
	}
}

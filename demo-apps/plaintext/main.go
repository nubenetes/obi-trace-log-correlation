package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	// Standard library logger emits free-form plain text (NOT JSON)
	// Example: "2026/10/06 14:00:00 payment authorized for user=alice amount=$99"
	// OBI's plain_text log enricher will append:
	// "trace_id=... span_id=..."
	log.SetOutput(os.Stdout)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK\n"))
	})

	http.HandleFunc("/legacy-order", func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		// Plain text log line
		log.Printf("legacy transaction executed user=john_doe action=submit_order item=SKU-9901")

		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "legacy order accepted in %v\n", time.Since(start))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8084"
	}

	log.Printf("legacy plaintext service listening on :%s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

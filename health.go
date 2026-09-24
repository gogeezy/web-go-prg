package main

import (
	"context"
	"database/sql"
	"net/http"
	"time"
)

// healthHandler checks whether the HTTP server is running.
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("OK"))
}

// readyHandler checks whether PostgreSQL is accessible.
func readyHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		if err := db.PingContext(ctx); err != nil {
			http.Error(
				w,
				"Database unavailable",
				http.StatusServiceUnavailable,
			)
			return
		}

		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("READY"))
	}
}

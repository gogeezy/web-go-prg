package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMiddlewarePreservesErrorStatus(t *testing.T) {
	failingHandler := http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			http.Error(
				w,
				"Database unavailable",
				http.StatusServiceUnavailable,
			)
		},
	)

	handler := loggingMiddleware(
		metricsMiddleware(failingHandler),
	)

	req := httptest.NewRequest(
		http.MethodGet,
		"/readyz",
		nil,
	)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf(
			"expected HTTP 503, got HTTP %d",
			rec.Code,
		)
	}
}

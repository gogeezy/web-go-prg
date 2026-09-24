package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func TestMetricsEndpoint(t *testing.T) {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", healthHandler)
	mux.Handle("/metrics", promhttp.Handler())

	handler := metricsMiddleware(mux)

	// Generate an HTTP request to populate our metric.
	healthReq := httptest.NewRequest(
		http.MethodGet,
		"/healthz",
		nil,
	)
	healthRec := httptest.NewRecorder()

	handler.ServeHTTP(healthRec, healthReq)

	if healthRec.Code != http.StatusOK {
		t.Fatalf(
			"health endpoint returned %d",
			healthRec.Code,
		)
	}

	// Request the Prometheus metrics endpoint.
	metricsReq := httptest.NewRequest(
		http.MethodGet,
		"/metrics",
		nil,
	)
	metricsRec := httptest.NewRecorder()

	handler.ServeHTTP(metricsRec, metricsReq)

	if metricsRec.Code != http.StatusOK {
		t.Fatalf(
			"metrics endpoint returned %d",
			metricsRec.Code,
		)
	}

	body := metricsRec.Body.String()

	if !strings.Contains(
		body,
		"app_http_requests_total",
	) {
		t.Fatal("custom HTTP counter not found")
	}

	if !strings.Contains(
		body,
		"app_http_request_duration_seconds",
	) {
		t.Fatal("custom HTTP histogram not found")
	}
}

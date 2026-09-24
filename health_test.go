package main

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	healthHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	if rec.Body.String() != "OK" {
		t.Fatalf("unexpected response: %q", rec.Body.String())
	}
}

func TestReadyHandler(t *testing.T) {
	tests := []struct {
		name       string
		pingError  error
		wantStatus int
	}{
		{
			name:       "database available",
			wantStatus: http.StatusOK,
		},
		{
			name:       "database unavailable",
			pingError:  errors.New("database unavailable"),
			wantStatus: http.StatusServiceUnavailable,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			db, mock, err := sqlmock.New(sqlmock.MonitorPingsOption(true))
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()

			mock.ExpectPing().WillReturnError(tt.pingError)

			req := httptest.NewRequest(
				http.MethodGet,
				"/readyz",
				nil,
			)
			rec := httptest.NewRecorder()

			readyHandler(db)(rec, req)

			if rec.Code != tt.wantStatus {
				t.Fatalf(
					"expected %d, got %d",
					tt.wantStatus,
					rec.Code,
				)
			}

			if err := mock.ExpectationsWereMet(); err != nil {
				t.Fatal(err)
			}
		})
	}
}

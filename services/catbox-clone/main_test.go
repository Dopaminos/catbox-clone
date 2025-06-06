package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func TestUploadHandler(t *testing.T) {
	os.RemoveAll("/app") // ensure /app exists fresh
	err := os.MkdirAll("/app/uploads", 0755)
	if err != nil {
		t.Fatalf("failed to create /app/uploads: %v", err)
	}
	defer os.RemoveAll("/app")

	formData := bytes.NewBufferString("----WebKitFormBoundary123\nContent-Disposition: form-data; name=\"file\"; filename=\"test.txt\"\nContent-Type: text/plain\n\ntest\n----WebKitFormBoundary123--")
	req, err := http.NewRequest("POST", "/upload", formData)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "multipart/form-data; boundary=--WebKitFormBoundary123")
	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(uploadHandler)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}
	if !strings.Contains(rr.Body.String(), "File Uploaded Successfully") {
		t.Errorf("handler returned unexpected body: got %v", rr.Body.String())
	}
}

func TestMetricsHandler(t *testing.T) {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(storageBytes)
	prometheus.MustRegister(networkBytesSent)
	prometheus.MustRegister(networkBytesReceived)

	storageBytes.Set(123) // trigger metric output

	req, err := http.NewRequest("GET", "/metrics", nil)
	if err != nil {
		t.Fatal(err)
	}
	rr := httptest.NewRecorder()
	handler := promhttp.Handler()
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}
	if !strings.Contains(rr.Body.String(), "catbox_storage_bytes") {
		t.Errorf("handler returned unexpected body: got %v", rr.Body.String())
	}
}

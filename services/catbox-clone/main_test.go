package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func TestUploadHandler(t *testing.T) {
	uploadDir := t.TempDir()
	t.Setenv("UPLOAD_DIR", uploadDir) 

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", "test.txt")
	if err != nil {
		t.Fatalf("failed to create form file: %v", err)
	}
	_, err = part.Write([]byte("test content"))
	if err != nil {
		t.Fatalf("failed to write form file: %v", err)
	}
	writer.Close()

	req, err := http.NewRequest("POST", "/upload", body)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(uploadHandler)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v, body: %v", status, http.StatusOK, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), "File Uploaded Successfully") {
		t.Errorf("handler returned unexpected body: got %v", rr.Body.String())
	}

	savedFile := filepath.Join(uploadDir, "test.txt")
	if _, err := os.Stat(savedFile); os.IsNotExist(err) {
		t.Errorf("file was not saved at %v", savedFile)
	}
}

func TestMetricsHandler(t *testing.T) {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(storageBytes)
	prometheus.MustRegister(networkBytesSent)
	prometheus.MustRegister(networkBytesReceived)

	storageBytes.Set(123) // Trigger metric output

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

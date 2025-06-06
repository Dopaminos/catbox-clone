package main

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Define Prometheus metrics
var (
    httpRequestsTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )
    httpRequestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "Duration of HTTP requests in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "path"},
    )
    storageBytes = prometheus.NewGauge(
        prometheus.GaugeOpts{
            Name: "catbox_storage_bytes",
            Help: "Total bytes used in uploads directory",
        },
    )
    networkBytesSent = prometheus.NewCounter(
        prometheus.CounterOpts{
            Name: "catbox_network_bytes_sent_total",
            Help: "Total bytes sent in HTTP responses",
        },
    )
    networkBytesReceived = prometheus.NewCounter(
        prometheus.CounterOpts{
            Name: "catbox_network_bytes_received_total",
            Help: "Total bytes received in HTTP requests",
        },
    )
)


// Middleware to track request metrics
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		if r.Body != nil {
			body, err := ioutil.ReadAll(r.Body)
			if err == nil {
				networkBytesReceived.Add(float64(len(body)))
				r.Body = io.NopCloser(bytes.NewReader(body))
			}
		}
		next.ServeHTTP(rw, r)
		duration := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", rw.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
		networkBytesSent.Add(float64(rw.bytesWritten))
	})
}

// Custom response writer to track bytes sent
type responseWriter struct {
	http.ResponseWriter
	statusCode   int
	bytesWritten int
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	n, err := rw.ResponseWriter.Write(b)
	rw.bytesWritten += n
	return n, err
}

func (rw *responseWriter) WriteHeader(statusCode int) {
	rw.statusCode = statusCode
	rw.ResponseWriter.WriteHeader(statusCode)
}

// Update storage metrics
func updateStorageMetrics() {
	totalSize := int64(0)
	filepath.Walk("/app/uploads", func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			totalSize += info.Size()
		}
		return nil
	})
	storageBytes.Set(float64(totalSize))
}

// Root handler with HTML frontend (drag-and-drop)
func rootHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprint(w, `
		<!DOCTYPE html>
		<html>
		<head>
			<title>catbox-clone</title>
			<style>
				body { font-family: Arial, sans-serif; text-align: center; padding: 20px; }
				.drop-zone { border: 2px dashed #ccc; padding: 20px; margin: 20px auto; width: 300px; }
				.drop-zone.dragover { background-color: #e0e0e0; }
			</style>
		</head>
		<body>
			<h1>Welcome to catbox-clone</h1>
			<div id="drop-zone" class="drop-zone">
				<p>Drag and drop a file here or click to select</p>
				<form id="upload-form" enctype="multipart/form-data" action="/upload" method="post">
					<input type="file" id="file-input" name="file" style="display: none;">
					<input type="submit" value="Upload">
				</form>
			</div>
			<p id="message"></p>
			<script>
				const dropZone = document.getElementById('drop-zone');
				const fileInput = document.getElementById('file-input');
				const form = document.getElementById('upload-form');
				const message = document.getElementById('message');

				dropZone.addEventListener('dragover', (e) => {
					e.preventDefault();
					dropZone.classList.add('dragover');
				});

				dropZone.addEventListener('dragleave', () => {
					dropZone.classList.remove('dragover');
				});

				dropZone.addEventListener('drop', (e) => {
					e.preventDefault();
					dropZone.classList.remove('dragover');
					const files = e.dataTransfer.files;
					if (files.length > 0) {
						fileInput.files = files;
						form.submit();
					}
				});

				dropZone.addEventListener('click', () => {
					fileInput.click();
				});

				fileInput.addEventListener('change', () => {
					if (fileInput.files.length > 0) {
						form.submit();
					}
				});
			</script>
		</body>
		</html>
	`)
}

// File server handler for uploaded files
func fileHandler(w http.ResponseWriter, r *http.Request) {
	filename := r.URL.Path[len("/files/"):]
	filePath := filepath.Join("/app/uploads", filename)
	http.ServeFile(w, r, filePath)
}

// Upload handler with file link
func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	err := r.ParseMultipartForm(10 << 20) // 10MB max
	if err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}

	file, handler, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "Failed to get file", http.StatusBadRequest)
		return
	}
	defer file.Close()

	f, err := os.Create(filepath.Join("/app/uploads", handler.Filename))
	if err != nil {
		http.Error(w, "Failed to save file", http.StatusInternalServerError)
		return
	}
	defer f.Close()

	_, err = io.Copy(f, file)
	if err != nil {
		http.Error(w, "Failed to save file", http.StatusInternalServerError)
		return
	}

	updateStorageMetrics()

	// Generate file URL (using service ClusterIP or localhost for dev)
	fileURL := fmt.Sprintf("http://localhost:8080/files/%s", handler.Filename)
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprintf(w, `
		<!DOCTYPE html>
		<html>
		<head>
			<title>catbox-clone Upload Success</title>
		</head>
		<body>
			<h1>File Uploaded Successfully</h1>
			<p>File: %s</p>
			<p><a href="%s">Download %s</a></p>
			<p><a href="/">Upload another file</a></p>
		</body>
		</html>
	`, handler.Filename, fileURL, handler.Filename)
}

func main() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(storageBytes)
	prometheus.MustRegister(networkBytesSent)
	prometheus.MustRegister(networkBytesReceived)

	if err := os.MkdirAll("/app/uploads", 0755); err != nil {
		log.Fatalf("Failed to create uploads directory: %v", err)
	}

	updateStorageMetrics()

	mux := http.NewServeMux()
	mux.HandleFunc("/", rootHandler)
	mux.HandleFunc("/upload", uploadHandler)
	mux.HandleFunc("/files/", fileHandler)
	mux.Handle("/metrics", promhttp.Handler())

	handler := metricsMiddleware(mux)

	log.Println("Starting server on :8080")
	if err := http.ListenAndServe(":8080", handler); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

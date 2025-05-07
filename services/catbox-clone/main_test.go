package main

import (
    "net/http"
    "net/http/httptest"
    "testing"
)

func TestRootHandler(t *testing.T) {
    req, err := http.NewRequest("GET", "/", nil)
    if err != nil {
        t.Fatal(err)
    }
    rr := httptest.NewRecorder()
    handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Write([]byte("OK"))
    })
    handler.ServeHTTP(rr, req)
    if status := rr.Code; status != http.StatusOK {
        t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
    }
    if rr.Body.String() != "OK" {
        t.Errorf("handler returned unexpected body: got %v want %v", rr.Body.String(), "OK")
    }
}

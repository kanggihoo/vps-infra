package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPortalHandlerServesStaticFilesAndFallsBackToIndex(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, root, "index.html", "<div id=\"root\"></div>")
	mustWrite(t, root, "assets/app.js", "console.log('ok')")

	handler := newPortalHandler(root)

	assertResponse(t, handler, "/assets/app.js", http.StatusOK, "console.log('ok')")
	assertResponse(t, handler, "/services", http.StatusOK, "<div id=\"root\"></div>")
}

func TestPortalHandlerBlocksDotfiles(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, root, "index.html", "<div id=\"root\"></div>")
	mustWrite(t, root, ".env", "SECRET=value")

	handler := newPortalHandler(root)

	assertResponse(t, handler, "/.env", http.StatusNotFound, "")
}

func mustWrite(t *testing.T, root string, name string, contents string) {
	t.Helper()
	path := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertResponse(t *testing.T, handler http.Handler, path string, wantStatus int, wantBody string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != wantStatus {
		t.Fatalf("%s status = %d, want %d", path, rec.Code, wantStatus)
	}
	if wantBody != "" && !strings.Contains(rec.Body.String(), wantBody) {
		t.Fatalf("%s body = %q, want substring %q", path, rec.Body.String(), wantBody)
	}
}

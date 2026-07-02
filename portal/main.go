package main

import (
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	root := getenv("PORTAL_STATIC_DIR", "dist")
	addr := getenv("PORTAL_ADDR", ":8080")

	log.Printf("portal serving %s on %s", root, addr)
	if err := http.ListenAndServe(addr, newPortalHandler(root)); err != nil {
		log.Fatal(err)
	}
}

func getenv(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func newPortalHandler(root string) http.Handler {
	fileServer := http.FileServer(http.Dir(root))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		cleanPath := filepath.Clean("/" + r.URL.Path)
		if hasDotfile(cleanPath) {
			http.NotFound(w, r)
			return
		}

		requested := filepath.Join(root, filepath.FromSlash(cleanPath))
		if info, err := os.Stat(requested); err == nil && !info.IsDir() {
			fileServer.ServeHTTP(w, r)
			return
		} else if err != nil && !errors.Is(err, os.ErrNotExist) {
			http.Error(w, "failed to read file", http.StatusInternalServerError)
			return
		}

		r2 := r.Clone(r.Context())
		r2.URL.Path = "/"
		fileServer.ServeHTTP(w, r2)
	})
}

func hasDotfile(path string) bool {
	for _, part := range strings.Split(path, "/") {
		if strings.HasPrefix(part, ".") {
			return true
		}
	}
	return false
}

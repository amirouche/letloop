package main

import (
	"fmt"
	"net/http"
	"os"
	"runtime"
	"sync"
	"time"
)

var (
	count int
	mu    sync.Mutex
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "usage: %s <port>\n", os.Args[0])
		os.Exit(1)
	}

	port := os.Args[1]
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/increment", handleIncrement)
	http.HandleFunc("/sleep", handleSleep)

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           http.DefaultServeMux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil {
		fmt.Fprintf(os.Stderr, "server error: %v\n", err)
		os.Exit(1)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" || (r.Method != "GET" && r.Method != "HEAD") {
		http.NotFound(w, r)
		return
	}

	mu.Lock()
	c := count
	mu.Unlock()

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, `<html><body>
<h1>Count: %d</h1>
<p>Press Ctrl-C for graceful shutdown</p>
<form method="POST" action="/increment">
<button type="submit">Increment</button>
</form>
<footer><small>Go %s | net/http (stdlib) | epoll | GOMAXPROCS=1 | go build</small></footer>
</body></html>`, c, runtime.Version())
}

func handleIncrement(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.NotFound(w, r)
		return
	}

	mu.Lock()
	count++
	mu.Unlock()

	http.Redirect(w, r, "/", http.StatusFound)
}

func handleSleep(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		http.NotFound(w, r)
		return
	}

	time.Sleep(1 * time.Second)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, `<html><body><h1>Slept 1 second (via time.Sleep)</h1></body></html>`)
}

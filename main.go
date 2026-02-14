package main

import (
	"html/template"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"web-go-prg/internal/calculator"
)

var (
	welcomeTmpl   *template.Template
	calculatorTmpl *template.Template
)

func init() {
	var err error
	welcomeTmpl, err = template.ParseFiles("templates/welcome.html")
	if err != nil {
		log.Fatal(err)
	}
	calculatorTmpl, err = template.ParseFiles("templates/calculator.html")
	if err != nil {
		log.Fatal(err)
	}
}

type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(code int) {
	if rw.status == 0 {
		rw.status = code
		rw.ResponseWriter.WriteHeader(code)
	}
}

func (rw *responseWriter) Write(p []byte) (n int, err error) {
	if rw.status == 0 {
		rw.status = http.StatusOK
	}
	return rw.ResponseWriter.Write(p)
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		wrapped := &responseWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(wrapped, r)
		if wrapped.status == 0 {
			wrapped.status = http.StatusOK
		}
		log.Printf("%s %s %d %v", r.Method, r.URL.Path, wrapped.status, time.Since(start))
	})
}

func welcomeHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := welcomeTmpl.Execute(w, nil); err != nil {
		log.Printf("template execute: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

type calcData struct {
	A         string
	B         string
	Result    float64
	HasResult bool
	Error     string
}

func calculatorHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	if r.Method == http.MethodGet {
		if err := calculatorTmpl.Execute(w, calcData{}); err != nil {
			log.Printf("template execute: %v", err)
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		}
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	if err := r.ParseForm(); err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	aStr := r.PostFormValue("a")
	bStr := r.PostFormValue("b")

	a, err := strconv.ParseFloat(aStr, 64)
	if err != nil {
		calculatorTmpl.Execute(w, calcData{A: aStr, B: bStr, Error: "Неверное число a"})
		return
	}
	b, err := strconv.ParseFloat(bStr, 64)
	if err != nil {
		calculatorTmpl.Execute(w, calcData{A: aStr, B: bStr, Error: "Неверное число b"})
		return
	}

	result := calculator.Sum(a, b)
	data := calcData{
		A:         aStr,
		B:         bStr,
		Result:    result,
		HasResult: true,
	}
	if err := calculatorTmpl.Execute(w, data); err != nil {
		log.Printf("template execute: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port

	mux := http.NewServeMux()
	mux.HandleFunc("/", welcomeHandler)
	mux.HandleFunc("/calculator", calculatorHandler)

	log.Printf("Listening on %s", addr)
	if err := http.ListenAndServe(addr, loggingMiddleware(mux)); err != nil {
		log.Fatal(err)
	}
}

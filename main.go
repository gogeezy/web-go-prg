package main

import (
	"context"
	"database/sql"
	"html/template"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"web-go-prg/internal/calculator"
	"web-go-prg/internal/history"
)

var (
	welcomeTmpl    *template.Template
	calculatorTmpl *template.Template
	historyRepo    *history.Repository
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
	History   []history.Entry
}

func loadHistory(ctx context.Context) ([]history.Entry, error) {
	return historyRepo.ListRecent(ctx, 50)
}

func calculatorHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	ctx := r.Context()

	if r.Method == http.MethodGet {
		hist, err := loadHistory(ctx)
		if err != nil {
			log.Printf("list history: %v", err)
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}
		if err := calculatorTmpl.Execute(w, calcData{History: hist}); err != nil {
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

	hist, err := loadHistory(ctx)
	if err != nil {
		log.Printf("list history: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	a, err := strconv.ParseFloat(aStr, 64)
	if err != nil {
		calculatorTmpl.Execute(w, calcData{A: aStr, B: bStr, Error: "Неверное число a", History: hist})
		return
	}
	b, err := strconv.ParseFloat(bStr, 64)
	if err != nil {
		calculatorTmpl.Execute(w, calcData{A: aStr, B: bStr, Error: "Неверное число b", History: hist})
		return
	}

	result := calculator.Sum(a, b)
	if err := historyRepo.InsertSum(ctx, a, b, result); err != nil {
		log.Printf("insert history: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	hist, err = loadHistory(ctx)
	if err != nil {
		log.Printf("list history: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	data := calcData{
		A:         aStr,
		B:         bStr,
		Result:    result,
		HasResult: true,
		History:   hist,
	}
	if err := calculatorTmpl.Execute(w, data); err != nil {
		log.Printf("template execute: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://postgres:postgres@localhost:5432/web_go_prg?sslmode=disable"
	}

	db, err := sql.Open("pgx", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(time.Hour)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		log.Fatalf("database ping: %v", err)
	}
	log.Printf("postgres: connected")

	historyRepo = history.NewRepository(db)
	if err := historyRepo.EnsureSchema(ctx); err != nil {
		log.Fatalf("ensure schema: %v", err)
	}
	log.Printf("postgres: ensured schema (table operation_history if missing)")

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

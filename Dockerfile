# СБОРКА
FROM golang:1.23-bookworm as builder
WORKDIR /src
ENV GOTOOLCHAIN=auto

COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /web-go-prg .

# ==== Стадия 2: Запуск ====
FROM gcr.io/distroless/static-debian12:nonroot 
WORKDIR /app
COPY --from=builder /web-go-prg  .
COPY --from=builder /src/templates ./templates
USER nonroot
ENTRYPOINT ["/app/web-go-prg"]

FROM golang:1.22 AS builder

WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

FROM alpine:latest

WORKDIR /app
COPY --from=builder /app/app .
RUN mkdir uploads

EXPOSE 8080
CMD ["./app"]

FROM golang:1.23-alpine AS build

WORKDIR /app
COPY go.mod ./
COPY go.sum ./
RUN go mod download

COPY . .
RUN go build -o /bin/api ./cmd/api

FROM alpine:3.20
RUN adduser -D appuser
WORKDIR /app
COPY --from=build /app/migrations ./migrations
COPY --from=build /bin/api /usr/local/bin/api
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
CMD ["api"]

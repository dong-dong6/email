FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
COPY cmd ./cmd
COPY internal ./internal
RUN go test ./... && go build -trimpath -ldflags="-s -w" -o /out/email-api ./cmd/api

FROM alpine:3.20
WORKDIR /app
COPY --from=build /out/email-api /app/email-api
EXPOSE 8080
ENTRYPOINT ["/app/email-api"]

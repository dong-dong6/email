FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN go test ./... && go build -trimpath -ldflags="-s -w" -o /out/email-api ./cmd/api

FROM alpine:3.20
RUN apk add --no-cache su-exec \
  && adduser -D -H -u 10001 app \
  && mkdir -p /data/blobs \
  && chown -R app:app /data
WORKDIR /app
COPY --from=build /out/email-api /app/email-api
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
  && chown app:app /app/email-api /app/entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/email-api"]

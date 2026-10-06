FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /plaintext main.go

FROM alpine:3.20
COPY --from=build /plaintext /plaintext
EXPOSE 8084
USER 10001:10001
ENTRYPOINT ["/plaintext"]

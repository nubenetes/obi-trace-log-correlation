FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /backend main.go

FROM alpine:3.20
RUN apk --no-cache add ca-certificates curl
COPY --from=build /backend /backend
EXPOSE 8081
USER 10001:10001
ENTRYPOINT ["/backend"]

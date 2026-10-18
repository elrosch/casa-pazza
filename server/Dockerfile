# PocketBase (version pinned in go.mod) extended with push notifications.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
# Cross-compiles for the target platform, so arm64 images need no emulation.
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/pocketbase .

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /out/pocketbase /usr/local/bin/pocketbase

# Schema migrations and server-side hooks are versioned in this repo.
COPY pb_migrations /pb_migrations
COPY pb_hooks /pb_hooks
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8090
VOLUME /pb_data

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD wget -q --spider http://127.0.0.1:8090/api/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]

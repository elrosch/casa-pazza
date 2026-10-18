# PocketBase (version pinned in go.mod) extended with push notifications,
# serving the Flutter web app. Build from the repository root:
#   docker build -f server/Dockerfile .

# The web app is platform independent, so it is built once on the host
# platform. Keep the Flutter version in sync with .github/workflows/ci.yml.
FROM --platform=$BUILDPLATFORM ghcr.io/cirruslabs/flutter:3.41.6 AS web
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY tool tool
COPY web web
COPY lib lib
RUN tool/fetch_web_sqlite.sh \
    && flutter build web --release --no-web-resources-cdn

FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/*.go ./
# Cross-compiles for the target platform, so arm64 images need no emulation.
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w" -o /out/pocketbase .

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /out/pocketbase /usr/local/bin/pocketbase

# Schema migrations and server-side hooks are versioned in this repo.
COPY server/pb_migrations /pb_migrations
COPY server/pb_hooks /pb_hooks
COPY --from=web /app/build/web /pb_public
COPY server/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8090
VOLUME /pb_data

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD wget -q --spider http://127.0.0.1:8090/api/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]

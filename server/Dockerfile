FROM alpine:3.22

ARG PB_VERSION=0.40.5
ARG TARGETARCH

RUN apk add --no-cache ca-certificates unzip wget \
    && cd /tmp \
    && ZIP="pocketbase_${PB_VERSION}_linux_${TARGETARCH}.zip" \
    && URL="https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}" \
    && wget -q "$URL/$ZIP" "$URL/checksums.txt" \
    && grep " $ZIP\$" checksums.txt | sha256sum -c - \
    && unzip "$ZIP" pocketbase -d /usr/local/bin/ \
    && rm "$ZIP" checksums.txt

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

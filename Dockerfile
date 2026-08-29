# syntax=docker/dockerfile:1
FROM alpine:3

# Requirements: jq and rtrdump (from StayRTR v0.6.2 or later)
# https://github.com/bgp/stayrtr/releases
ARG STAYRTR_VERSION=v0.6.4
ARG TARGETARCH

LABEL org.opencontainers.image.title="rtrcheck" \
      org.opencontainers.image.description="Compares RTR serial and data with previous run" \
      org.opencontainers.image.source="https://github.com/lukastribus/rtrcheck" \
      org.opencontainers.image.licenses="ISC"

RUN apk add --no-cache jq ca-certificates curl

# pin rtrdump to a known release + checksum per architecture (see release digests on GitHub)
RUN set -eux; \
    case "$TARGETARCH" in \
        amd64) stayrtr_arch=x86_64; stayrtr_sha256=16e475aaa5cf7afe69cc5f738024a29ae624aaebee2b6fffd93944dd7e4e4f8c ;; \
        arm64) stayrtr_arch=arm64;  stayrtr_sha256=99869a30d0f43e9120226c7906495ee14b3b13c22bfa99926859b2cd67d538d0 ;; \
        *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/rtrdump \
        "https://github.com/bgp/stayrtr/releases/download/${STAYRTR_VERSION}/rtrdump-${STAYRTR_VERSION}-linux-${stayrtr_arch}"; \
    echo "${stayrtr_sha256}  /usr/local/bin/rtrdump" | sha256sum -c -; \
    chmod +x /usr/local/bin/rtrdump

COPY rtrcheck /usr/local/bin/rtrcheck
RUN chmod +x /usr/local/bin/rtrcheck

# non-root user; state files are written to the working directory (mount a volume there)
RUN addgroup -S rtrcheck && adduser -S -G rtrcheck -h /data rtrcheck && \
    mkdir -p /data && chown rtrcheck:rtrcheck /data
WORKDIR /data
VOLUME /data
USER rtrcheck

ENTRYPOINT ["rtrcheck"]

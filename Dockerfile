FROM alpine:latest
ARG TARGETARCH
RUN apk add --no-cache libuuid
COPY artifacts/letloop-linux-${TARGETARCH} /usr/local/bin/letloop
RUN chmod +x /usr/local/bin/letloop
ENTRYPOINT ["letloop"]

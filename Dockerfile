FROM alpine:latest
RUN apk add --no-cache libuuid
COPY letloop-linux-amd64/letloop /usr/local/bin/letloop
COPY letloop-linux-amd64/*.boot /usr/local/lib/
ENTRYPOINT ["letloop"]

FROM alpine:3.20

RUN apk add --no-cache clang-extra-tools findutils bash git

WORKDIR /work


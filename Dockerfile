FROM alpine:3.5

ADD entrypoint.sh /

ADD build.sh /
RUN /build.sh

USER backup
ENTRYPOINT /entrypoint.sh

FROM alpine:3.5

ADD build.sh /
RUN /build.sh

ADD entrypoint.sh /
USER backup
ENTRYPOINT /entrypoint.sh

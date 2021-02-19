FROM alpine:3.11

RUN apk update && \
  apk add --update \
    bash \
    easy-rsa \
    git \
    openssh-client \
    curl \
    ca-certificates \
    jq \
    python \
    py-yaml \
    py2-pip \
    libstdc++ \
    gpgme \
    git-crypt \
    && \
  rm -rf /var/cache/apk/*

RUN pip install ijson awscli
RUN adduser -h /backup -D backup

ARG KUBECTL_VERSION="1.17.0"
ARG KUBECTL_SHA256="6e0aaaffe5507a44ec6b1b8a0fb585285813b78cc045f8804e70a6aac9d1cb4c"

RUN curl -SL \
  "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
  chmod +x /usr/local/bin/kubectl
RUN echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - || exit 10

COPY entrypoint.sh /
USER backup
ENTRYPOINT ["/entrypoint.sh"]

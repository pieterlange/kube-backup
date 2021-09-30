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

ARG KUBECTL_VERSION="1.21.5"
ARG KUBECTL_SHA256="060ede75550c63bdc84e14fcc4c8ab3017f7ffc032fc4cac3bf20d274fab1be4"

RUN curl -SL \
  "https://dl.k8s.io/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
  chmod +x /usr/local/bin/kubectl
RUN echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - || exit 10

COPY entrypoint.sh /
USER backup
ENTRYPOINT ["/entrypoint.sh"]

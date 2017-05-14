FROM alpine:3.5

ENV KUBECTL_VERSION 1.6.2
ENV KUBECTL_SHA256 9beec3e8a9208da5cac479a164a61bf6a7b0b8716c338f866c4316680f0e9d98
ENV KUBECTL_URI https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl

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
    && \
  rm -rf /var/cache/apk/*

RUN curl -SL ${KUBECTL_URI} -o kubectl && chmod +x kubectl
RUN echo "${KUBECTL_SHA256}  kubectl" | sha256sum -c - || exit 10

RUN pip install ijson awscli
RUN adduser -h /backup -D backup

COPY entrypoint.sh /
USER backup
ENTRYPOINT ["/entrypoint.sh"]

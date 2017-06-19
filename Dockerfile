FROM alpine:3.6

ENV KUBECTL_VERSION 1.6.5
ENV KUBECTL_SHA256 646544e223f91b32e5d61133560cc85dd708805a97d8f31e871fc9d86dc9aad3
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

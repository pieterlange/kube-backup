FROM alpine:3.17

RUN apk update && \
  apk add --update \
    bash \
    easy-rsa \
    git \
    openssh-client \
    curl \
    ca-certificates \
    jq \
    python3 \
    py-yaml \
    py3-pip \
    libstdc++ \
    gpgme \
    git-crypt \
    && \
  rm -rf /var/cache/apk/*

RUN pip install ijson awscli
RUN adduser -h /backup -D backup

ENV KUBECTL_VERSION 1.23.6
ENV KUBECTL_SHA256 703a06354bab9f45c80102abff89f1a62cbc2c6d80678fd3973a014acc7c500a
ENV KUBECTL_URI https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl

RUN curl -SL ${KUBECTL_URI} -o kubectl && chmod +x kubectl

RUN echo "${KUBECTL_SHA256}  kubectl" | sha256sum -c - || exit 10
ENV PATH="/:${PATH}"

COPY entrypoint.sh /
USER backup
ENTRYPOINT ["/entrypoint.sh"]

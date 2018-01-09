FROM alpine:3.7

ENV KUBECTL_VERSION 1.8.4
ENV KUBECTL_SHA256 fb3cbf25e71f414381e8a6b8a2dc2abb19344feea660ac0445ccf5d43a093f10
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
    libstdc++ \
    gpgme \
    libressl-dev \
    make \
    g++ \
    && \
  git clone https://github.com/AGWA/git-crypt.git && \
  make --directory git-crypt && \
  make --directory git-crypt install && \
  rm -rf git-crypt && \
  apk del libressl-dev make g++ && \
  rm -rf /var/cache/apk/*

RUN curl -SL ${KUBECTL_URI} -o kubectl && chmod +x kubectl
RUN echo "${KUBECTL_SHA256}  kubectl" | sha256sum -c - || exit 10
ENV PATH="/:${PATH}"

RUN pip install ijson awscli
RUN adduser -h /backup -D backup

COPY entrypoint.sh /
USER backup
ENTRYPOINT ["/entrypoint.sh"]

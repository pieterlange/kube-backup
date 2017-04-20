#!/bin/sh

set -ex
KUBECTL_VERSION=1.6.2

get_bin()
{
  hash="$1"
  url="$2"
  f=$(basename "$url")

  curl -sSL "$url" -o "$f"
  echo "$hash  $f" | sha256sum -c - || exit 10
  chmod +x "$f"
}
apk add --update bash easy-rsa git openssh-client curl ca-certificates jq python py-yaml py2-pip

pip install ijson

get_bin 9beec3e8a9208da5cac479a164a61bf6a7b0b8716c338f866c4316680f0e9d98 \
    "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

adduser -h /backup -D backup

# Cleanup
rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

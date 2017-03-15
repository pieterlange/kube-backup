#!/bin/sh

set -ex
KUBECTL_VERSION=1.5.4

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

get_bin 1d9be6531f9830798b94d2a3ba6d07592ac664b8e12a8ddf201dd815719b9563 \
    "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

adduser -h /backup -D backup

# Cleanup
rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

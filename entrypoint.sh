#!/bin/bash -e

set -x 

if [ -z "$NAMESPACES" ]; then
  NAMESPACES=$(kubectl get ns -o jsonpath={.items[*].metadata.name})
fi

RESOURCETYPES="${RESOURCETYPES:-"ingress deployment configmap svc rc ds crd networkpolicy statefulset storageclass cronjob"}"
GLOBALRESOURCES="${GLOBALRESOURCES:-"namespace storageclasses"}"

# Initialize git repo
[ -z "$GIT_REPO" ] && echo "Need to define GIT_REPO environment variable" && exit 1
GIT_REPO_PATH="${GIT_REPO_PATH:-"/backup/git"}"
GIT_PREFIX_PATH="${GIT_PREFIX_PATH:-"."}"
GIT_USERNAME="${GIT_USERNAME:-"kube-backup"}"
GIT_EMAIL="${GIT_EMAIL:-"kube-backup@example.com"}"
GIT_BRANCH="${GIT_BRANCH:-"master"}"
GITCRYPT_ENABLE="${GITCRYPT_ENABLE:-"false"}"
GITCRYPT_PRIVATE_KEY="${GITCRYPT_PRIVATE_KEY:-"/secrets/gpg-private.key"}"
GITCRYPT_SYMMETRIC_KEY="${GITCRYPT_SYMMETRIC_KEY:-"/secrets/symmetric.key"}"

if [[ ! -f /backup/.ssh/id_rsa ]] ; then
    git config --global credential.helper '!aws codecommit credential-helper $@'
    git config --global credential.UseHttpPath true
fi
git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"

test -d "$GIT_REPO_PATH" || git clone --depth 1 "$GIT_REPO" "$GIT_REPO_PATH" --branch "$GIT_BRANCH" || git clone "$GIT_REPO" "$GIT_REPO_PATH"
cd "$GIT_REPO_PATH"
git checkout "${GIT_BRANCH}" || git checkout -b "${GIT_BRANCH}"
git stash
if [ "$GITCRYPT_ENABLE" = "true" ]; then
  if [ -f "$GITCRYPT_PRIVATE_KEY" ]; then
    gpg --allow-secret-key-import --import "$GITCRYPT_PRIVATE_KEY"
    git-crypt unlock
  elif [ -f "$GITCRYPT_SYMMETRIC_KEY" ]; then
    git-crypt unlock "$GITCRYPT_SYMMETRIC_KEY"
  else
    echo "[ERROR] Please verify your env variables (GITCRYPT_PRIVATE_KEY or GITCRYPT_SYMMETRIC_KEY)"
    exit 1
  fi
fi
cd "$GIT_REPO_PATH/$GIT_PREFIX_PATH"
git rm -r **/*.yaml || true

# Start kubernetes state export
for resource in $GLOBALRESOURCES; do
  [ -d "$GIT_REPO_PATH/$GIT_PREFIX_PATH" ] || mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH"
  echo "Exporting resource: ${resource}" > /dev/stderr
  kubectl get --export -o=json "$resource" | jq --sort-keys \
      'del(
          .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
          .items[].metadata.annotations."control-plane.alpha.kubernetes.io/leader",
          .items[].metadata.uid,
          .items[].metadata.selfLink,
          .items[].metadata.resourceVersion,
          .items[].metadata.creationTimestamp,
          .items[].metadata.generation
      )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${resource}.yaml"
done

for namespace in $NAMESPACES; do
  [ -d "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}" ] || mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}"

  for type in $RESOURCETYPES; do
    echo "[${namespace}] Exporting resources: ${type}" > /dev/stderr

    label_selector=""
    if [[ "$type" == 'configmap' && -z "${INCLUDE_TILLER_CONFIGMAPS:-}" ]]; then
      label_selector="-l OWNER!=TILLER"
    fi

    kubectl --namespace="${namespace}" get --export -o=json "$type" $label_selector | jq --sort-keys \
        'select(.type!="kubernetes.io/service-account-token") |
        del(
            .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
            .items[].metadata.annotations."control-plane.alpha.kubernetes.io/leader",
            .items[].spec.clusterIP,
            .items[].metadata.uid,
            .items[].metadata.selfLink,
            .items[].metadata.resourceVersion,
            .items[].metadata.creationTimestamp,
            .items[].metadata.generation,
            .items[].status
        )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}/${type}.yaml"
  done
done

git add .

if ! git diff-index --quiet HEAD -- ; then
    git commit -m "Automatic backup at $(date)"
    git push origin "${GIT_BRANCH}"
else
    echo "No change"
fi

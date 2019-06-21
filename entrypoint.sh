#!/bin/bash -e

if [ -z "$NAMESPACES" ]; then
    NAMESPACES=$(kubectl get ns -o jsonpath={.items[*].metadata.name})
fi

RESOURCETYPES="${RESOURCETYPES:-"ingress deployment configmap svc rc ds networkpolicy statefulset cronjob pvc"}"
GLOBALRESOURCES="${GLOBALRESOURCES:-"namespace storageclass clusterrole clusterrolebinding customresourcedefinition"}"

# Initialize git repo
[ -z "$DRY_RUN" ] && [ -z "$GIT_REPO" ] && echo "Need to define GIT_REPO environment variable" && exit 1
GIT_REPO_PATH="${GIT_REPO_PATH:-"/backup/git"}"
GIT_PREFIX_PATH="${GIT_PREFIX_PATH:-"."}"
GIT_USERNAME="${GIT_USERNAME:-"kube-backup"}"
GIT_EMAIL="${GIT_EMAIL:-"kube-backup@example.com"}"
GIT_BRANCH="${GIT_BRANCH:-"master"}"
GITCRYPT_ENABLE="${GITCRYPT_ENABLE:-"false"}"
GITCRYPT_PRIVATE_KEY="${GITCRYPT_PRIVATE_KEY:-"/secrets/gpg-private.key"}"
GITCRYPT_SYMMETRIC_KEY="${GITCRYPT_SYMMETRIC_KEY:-"/secrets/symmetric.key"}"

if [[ ! -f /backup/.ssh/id_rsa ]]; then
    git config --global credential.helper '!aws codecommit credential-helper $@'
    git config --global credential.UseHttpPath true
fi
[ -z "$DRY_RUN" ] && git config --global user.name "$GIT_USERNAME"
[ -z "$DRY_RUN" ] && git config --global user.email "$GIT_EMAIL"

[ -z "$DRY_RUN" ] && (test -d "$GIT_REPO_PATH" || git clone --depth 1 "$GIT_REPO" "$GIT_REPO_PATH" --branch "$GIT_BRANCH" || git clone "$GIT_REPO" "$GIT_REPO_PATH")
cd "$GIT_REPO_PATH"
[ -z "$DRY_RUN" ] && (git checkout "${GIT_BRANCH}" || git checkout -b "${GIT_BRANCH}")

mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH"
cd "$GIT_REPO_PATH/$GIT_PREFIX_PATH"

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

[ -z "$DRY_RUN" ] && git rm -r '*.yaml' --ignore-unmatch -f

# Start kubernetes state export
for resource in $GLOBALRESOURCES; do
    [ -d "$GIT_REPO_PATH/$GIT_PREFIX_PATH" ] || mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH"
    echo "Exporting resource: ${resource}" >/dev/stderr
    kubectl get -o=json "$resource" | jq --sort-keys \
        'del(
          .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
          .items[].metadata.annotations."control-plane.alpha.kubernetes.io/leader",
          .items[].metadata.uid,
          .items[].metadata.selfLink,
          .items[].metadata.resourceVersion,
          .items[].metadata.creationTimestamp,
          .items[].metadata.generation
      )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' >"$GIT_REPO_PATH/$GIT_PREFIX_PATH/${resource}.yaml"
done

for namespace in $NAMESPACES; do
    [ -d "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}" ] || mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}"

    for type in $RESOURCETYPES; do
        echo "[${namespace}] Exporting resources: ${type}" >/dev/stderr

        label_selector=""
        if [[ "$type" == 'configmap' && -z "${INCLUDE_TILLER_CONFIGMAPS:-}" ]]; then
            label_selector="-l OWNER!=TILLER"
        fi

        kubectl --namespace="${namespace}" get "$type" $label_selector -o custom-columns=SPACE:.metadata.namespace,KIND:..kind,NAME:.metadata.name --no-headers | while read -r a b name; do
            [ -z "$name" ] && continue

        # Service account tokens cannot be exported
        if [[ "$type" == 'secret' && $(kubectl get -n "${namespace}" -o jsonpath="{.type}" secret "$name") == "kubernetes.io/service-account-token" ]]; then
            continue
        fi

        kubectl --namespace="${namespace}" get -o=json "$type" "$name" | jq --sort-keys \
        'del(
            .metadata.annotations."control-plane.alpha.kubernetes.io/leader",
            .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
            .metadata.creationTimestamp,
            .metadata.generation,
            .metadata.resourceVersion,
            .metadata.selfLink,
            .metadata.uid,
            .spec.clusterIP,
            .status
        )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' >"$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}/${name}.${type}.yaml"
        done
    done
done

[ -z "$DRY_RUN" ] || exit

cd "${GIT_REPO_PATH}"
git add .

if ! git diff-index --quiet HEAD --; then
    git commit -m "Automatic backup at $(date)"
    git push origin "${GIT_BRANCH}"
else
    echo "No change"
fi

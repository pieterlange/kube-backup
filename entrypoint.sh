#!/bin/bash -e

allNamespaces=( $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}') )
declare -A allObjects=() # key: "namespace/resourceType" or resourceType, value: name list
declare -A selectedObjects=() # key: file name, value: kubectl command

# Find matching objects in the cluster
for resource in $RESOURCES; do
    if [[ $resource =~ ^([+-]?)([a-zA-Z]+):(([^/]+)/)?(.*) ]]; then # eg: '+deployments:test/db-*'
        direction="${BASH_REMATCH[1]:-+}"
        declare -l resourceType="${BASH_REMATCH[2]}"
        declare -l namespacePattern="${BASH_REMATCH[4]}"
        declare -l objectPattern="${BASH_REMATCH[5]}"
        objectsKeys=()

        # Get all matching objects from cluster and namespace scopes
        # TODO: Handle plural forms like ingress -> ingresses
        if [[ -n $namespacePattern ]]; then # namespace scope
            for namespace in ${allNamespaces[@]}; do
                if [[ $namespace = $namespacePattern ]]; then
                    objectsKeys=( ${objectsKeys[@]} $namespace/$resourceType )

                    if [[ ! ${allObjects[$namespace/$resourceType]:+xyz} ]]; then
                        echo "Querying all $resourceType in $namespace..."
                        allObjects[$namespace/$resourceType]=$(kubectl get $resourceType -n $namespace -o jsonpath='{.items[*].metadata.name}')
                    fi
                fi
            done
        else # cluster scope
            objectsKeys=( ${objectsKeys[@]} $resourceType )

            if [[ ! ${allObjects[$resourceType]:+xyz} ]]; then 
                echo "Querying all $resourceType in cluster-scope..."
                allObjects[$resourceType]=$(kubectl get $resourceType -o jsonpath='{.items[*].metadata.name}')
            fi
        fi

        # Assemble the object list
        if [[ ${#objectsKeys[@]} -ne 0 ]]; then
            for key in ${objectsKeys[@]}; do
                [[ $key = */* ]] && namespace=${key%%/*}
                for objectName in ${allObjects[$key]}; do
                    if [[ $objectName = $objectPattern ]]; then
                        fileName="$key.$objectName.yaml"
                        if [[ $direction = + ]]; then
                            selectedObjects[$fileName]="kubectl get $resourceType $objectName ${namespace:+--namespace} $namespace"
                        else
                            unset selectedObjects[$fileName]
                        fi
                    fi
                done
            done
        else
            echo "Warning: $resource doesn't match to anything!" >&2
        fi
    else
        echo "Warning: Invalid expression: $resource" >&2
    fi

    unset namespace
done

# Initialize git repo
[ -z "$DRY_RUN" ] && [ -z "$GIT_REPO" ] && echo "Need to define GIT_REPO environment variable" && exit 1
[ -z "$RESOURCES" ] && echo "Need to define RESOURCES environment variable" && exit 1
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

echo "Exporting ${#selectedObjects[@]} object(s):"
for objectKey in ${!selectedObjects[@]}; do
    fileName="$GIT_REPO_PATH/$GIT_PREFIX_PATH/$objectKey"
    kubectlCommand="${selectedObjects[$objectKey]}"

    mkdir -p "$(dirname "$fileName")"

    echo "Exporting to $fileName" >&2

    # echo Debug: $kubectlCommand
    $kubectlCommand -o=json | jq --sort-keys \
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
    )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > "$fileName"
done

[ -z "$DRY_RUN" ] || exit

cd "${GIT_REPO_PATH}"
git add .

if ! git diff-index --quiet HEAD --; then
    git -c user.name="$GIT_USERNAME" -c user.email="$GIT_EMAIL" commit -m "Automatic backup at $(date)"
    git push origin "${GIT_BRANCH}"
else
    echo "No changes"
fi

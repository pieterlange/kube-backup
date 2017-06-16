#!/bin/bash -e

if [ -z $NAMESPACES ]; then
  NAMESPACES=$(/kubectl get ns -o jsonpath={.items[*].metadata.name})
fi

RESOURCETYPES=${RESOURCETYPES:-"ingress deployment configmap svc rc ds thirdpartyresource networkpolicy statefulset storageclass cronjob"}
GLOBALRESOURCES=${GLOBALRESOURCES:-"namespace storageclasses"}

# Initialize git repo
[ -z $GIT_REPO ] && echo "Need to define GIT_REPO environment variable" && exit 1
GIT_USERNAME=${GIT_USERNAME:-kube-backup}
GIT_EMAIL=${GIT_EMAIL:-kube-backup@example.com}
GIT_BRANCH=${GIT_BRANCH:-master}

if [[ ! -f /backup/.ssh/id_rsa ]] ; then
    git config --global credential.helper '!aws codecommit credential-helper $@'
    git config --global credential.UseHttpPath true
fi
git config --global user.name $GIT_USERNAME
git config --global user.email $GIT_EMAIL

test -d /backup/git/ || git clone --depth 1 $GIT_REPO /backup/git --branch $GIT_BRANCH || git clone $GIT_REPO /backup/git
cd /backup/git/
git checkout ${GIT_BRANCH} || git checkout -b ${GIT_BRANCH}
git rm -r . || true

# Start kubernetes state export
for resource in $GLOBALRESOURCES; do
  echo "Exporting resource: ${resource}" > /dev/stderr
  /kubectl get --export -o=json $resource | jq --sort-keys \
      'del(
          .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
          .items[].metadata.annotations."control-plane.alpha.kubernetes.io/leader",
          .items[].metadata.uid,
          .items[].metadata.selfLink,
          .items[].metadata.resourceVersion,
          .items[].metadata.creationTimestamp,
          .items[].metadata.generation
      )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > /backup/git/${resource}.yaml
done

for namespace in $NAMESPACES; do
  [ -d /backup/git/${namespace} ] || mkdir -p /backup/git/${namespace}

  for type in $RESOURCETYPES; do
    echo "[${namespace}] Exporting resources: ${type}" > /dev/stderr

    label_selector=""
    if [[ $type == 'configmap' && -z "${INCLUDE_TILLER_CONFIGMAPS:-}" ]]; then
      label_selector="-l OWNER!=TILLER"
    fi

    /kubectl --namespace="${namespace}" get --export -o=json $type $label_selector | jq --sort-keys \
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
        )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > /backup/git/${namespace}/${type}.yaml
  done
done

git add .

if ! git diff-index --quiet HEAD -- ; then
    git commit -m "Automatic backup at $(date)"
    git push origin ${GIT_BRANCH}
else
    echo "No change"
fi

#!/bin/bash

if [ -z $NAMESPACES ]; then
  NAMESPACES=$(/kubectl get ns -o jsonpath={.items[*].metadata.name})
fi

RESOURCETYPES=${RESOURCETYPES:-"ingress deployment configmap svc rc ds thirdpartyresource networkpolicy statefulset storageclass cronjob"}

# Initialize git repo
[ -z $GIT_REPO ] && echo "Need to define GIT_REPO environment variable" && exit 1
GIT_USERNAME=${GIT_USERNAME:-kube-backup}
GIT_EMAIL=${GIT_EMAIL:-kube-backup@example.com}

git config --global user.name $GIT_USERNAME
git config --global user.email $GIT_EMAIL
git clone --depth 1 $GIT_REPO /backup/git

# Start kubernetes state export
for namespace in $NAMESPACES; do
  [ -d /backup/git/${namespace} ] || mkdir -p /backup/git/${namespace}

  for type in $RESOURCETYPES; do
    echo "[${namespace}] Exporting resources: ${type}"
    /kubectl --namespace="${namespace}" get --export -o=json $type | jq --sort-keys \
        'select(.type!="kubernetes.io/service-account-token") |
        del(
            .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
            .items[].spec.clusterIP,
            .items[].metadata.uid,
            .items[].metadata.selfLink,
            .items[].metadata.resourceVersion,
            .items[].metadata.creationTimestamp,
            .items[].metadata.generation,
            .items[].status,
            .items[].spec.template.spec.securityContext,
            .items[].spec.template.spec.dnsPolicy,
            .items[].spec.template.spec.terminationGracePeriodSeconds,
            .items[].spec.template.spec.restartPolicy
        )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' > /backup/git/${namespace}/${type}.yaml
  done
done

cd /backup/git/
git add .
git commit -m "Automatic backup at $(date)"
git push

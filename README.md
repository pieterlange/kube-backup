kube-backup
===========
[![Docker Repository on Quay](https://quay.io/repository/plange/kube-backup/status "Docker Repository on Quay")](https://quay.io/repository/plange/kube-backup)
[![Docker Repository on Docker Hub](https://img.shields.io/docker/automated/ptlange/kube-backup.svg "Docker Repository on Docker Hub")](https://hub.docker.com/r/ptlange/kube-backup/)

Quick 'n dirty kubernetes state backup script, designed to be ran as kubernetes Job. Think of it like [RANCID](http://www.shrubbery.net/rancid/) for kubernetes.

Props to @gianrubio for coming up with the idea.

Setup
-----
Use the deployment example ([ssh](cronjob-ssh.yaml) or [AWS CodeCommit](cronjob-codecommit.yaml) authentication) and deploy a kubernetes `CronJob` primitive in your kubernetes (1.5 and up) cluster ensuring backups of kubernetes resource definitions to your private git repo.

Define the following environment parameters:
  * `GIT_REPO` - GIT repo url. **Required**
  * `GIT_PREFIX_PATH` - Path to the subdirectory in your repository. Default: `.`
  * `NAMESPACES` - List of namespaces to export. Default: all
  * `GLOBALRESOURCES` - List of global resource types to export. Default: `namespace`
  * `RESOURCETYPES` - List of resource types to export. Default: `ingress deployment configmap svc rc ds networkpolicy statefulset storageclass cronjob`. Notice that `Secret` objects are intentionally not exported by default (see [git-crypt section](#git-crypt) for details).
  * `GIT_USERNAME` - Display name of git user. Default: `kube-backup`
  * `GIT_EMAIL` - Email address of git user. Default: `kube-backup@example.com`
  * `GIT_BRANCH` - Use a specific git branch . Default: `master`
  * `GITCRYPT_ENABLE` - Use git-crypt for data encryption. See [git-crypt section](#git-crypt) for details. Default: `false`
  * `GITCRYPT_PRIVATE_KEY` - Path to private gpg key for git-crypt. See [git-crypt section](#git-crypt) for details. Default: `/secrets/gpg-private.key`
  * `GITCRYPT_SYMMETRIC_KEY` - Path to shared symmetric key for git-crypt. See [git-crypt section](#git-crypt). Default: `/secrets/symmetric.key`

Choose one of two authentication mechanisms:

  * When using AWS CodeCommit and policy-based access from AWS, modify your cluster configuration to provide GitPull and GitPush access for that CodeCommit repo to your cluster. If using `kops`, the configuration will look something like this:

  ```yaml
    additionalPolicies:
      node: |
        [
          {
            "Effect": "Allow",
            "Action": [
              "codecommit:GitPull",
              "codecommit:GitPush"
            ],
            "Resource": "arn:aws:codecommit:<region>:<account name>:<repo-name>"
          }
        ]
  ```

  NOTE: in this deployment, the ssh volume and secret are not present.


  * When using a different repository (GitHub, BitBucket, etc.), mount a configured ssh directory in `/backup/.ssh` with the following files:

    * `known_hosts` - Preloaded with SSH host key of `$GIT_REPO` host.
    * `id_rsa` - SSH private key of user allowed to push to `$GIT_REPO`.

  Easiest way of doing this is:
  ```bash
  ssh-keygen -f ./id_rsa
  ssh-keyscan $YOUR_GIT_HOST > known_hosts

  kubectl create secret generic kube-backup-ssh -n kube-system --from-file=id_rsa --from-file=known_hosts
  ```

  NOTE: If `id_rsa` isn't found in your ssh directory, the backup script will assume you're using AWS CodeCommit.

Optional:
  * Modify the snapshot frequency in `spec.schedule` using the [cron format](https://en.wikipedia.org/wiki/Cron).
  * Modify the number of successful and failed finished jobs to retain in `spec.successfulJobsHistoryLimit` and `spec.failedJobsHistoryLimit`.
  * If using RBAC (1.6+), use the ClusterRole and ClusterRoleBindings in rbac.yaml.

git-crypt
---------
For security reasons `Secret` objects are not exported by default. However there is a possibility to store them safely using the [git-crypt project](https://github.com/AGWA/git-crypt).

#### Prerequisites
Your repository has to be already initialized with git-crypt. Minimal configuration is listed below. For details and full information see [using git-crypt](https://github.com/AGWA/git-crypt#using-git-crypt).

```
cd repo
git-crypt init
cat <<EOF > .gitattributes
*.secret.yaml filter=git-crypt diff=git-crypt
.gitattributes !filter !diff
EOF
git-crypt add-gpg-user <USER_ID>
git add -A
git commit -a -m "initialize git-crypt"
```

Optional:
  * You may choose any subdirectory for storing .gitattributes file (useful when using `GIT_PREFIX_PATH`).
  * You may encrypt additional files other than secret.yaml. Add additional lines before the .gitattribute filter. You may also use wildcard `*` to encrypt all files within the directory.

#### Enable git-crypt
To enable encryption feature:
  * Set pod environment variable `GITCRYPT_ENABLE` to `true`
    ```
    spec:
      containers:
      - env:
        - name: GITCRYPT_ENABLE
          value: "true"
    ```
  * Create additional `Secret` object containing **either** gpg-private or symmetric key
    ```
    apiVersion: v1
    kind: Secret
    metadata:
      name: kube-backup-gpg
      namespace: kube-system
    data:
      gpg-private.key: <base64_encoded_key>
      symmetric.key: <base64_encoded_key>
    ```
  * Mount keys from `Secret` as additional volume
    ```
    spec:
      containers:
      - volumeMounts:
        - mountPath: /secrets
          name: gpgkey
      volumes:
      - name: gpgkey
        secret:
          defaultMode: 420
          secretName: kube-backup-gpg
    ```
  * Add secret object name to `RESOURCETYPES` variable
    ```
    spec:
      containers:
      - env:
        - name: RESOURCETYPES
          value: "ingress deployment configmap secret svc rc ds thirdpartyresource networkpolicy statefulset storageclass cronjob"
    ```
  * If using RBAC (1.6+), add `secrets` to `resources`
    ```
    rules:
    - apiGroups: ["*"]
      resources: [
        "configmaps",
        "secrets",
    ```

  * (Optional): `$GITCRYPT_PRIVATE_KEY` and `$GITCRYPT_SYMMETRIC_KEY` variables are the combination of path where `Secret` volume is mounted and the name of item key from that object. If you change any value of them from the above example you may need to set this variables accordingly.


Result
------
All configured resources will be exported into a directory tree structure in YAML format following a `$namespace/$name.$type.yaml` file structure.

```
.
├── kube-system
│   ├── attachdetach-controller.serviceaccounts.yaml
│   ├── canal-config.configmap.yaml
│   ├── canal.daemonset.yaml
│   ├── canal.serviceaccounts.yaml
│   ├── certificate-controller.serviceaccounts.yaml
│   ├── cronjob-controller.serviceaccounts.yaml
│   ├── daemon-set-controller.serviceaccounts.yaml
│   ├── default.serviceaccounts.yaml
│   ├── deployment-controller.serviceaccounts.yaml
│   ├── disruption-controller.serviceaccounts.yaml
│   ├── dns-controller.deployment.yaml
│   ├── dns-controller.serviceaccounts.yaml
│   ├── endpoint-controller.serviceaccounts.yaml
│   ├── generic-garbage-collector.serviceaccounts.yaml
│   ├── horizontal-pod-autoscaler.serviceaccounts.yaml
│   ├── job-controller.serviceaccounts.yaml
│   ├── kube-backup-gpg.secret.yaml
│   ├── kube-backup.serviceaccounts.yaml
│   ├── kube-backup-ssh.secret.yaml
│   ├── kube-dns-autoscaler.configmap.yaml
│   ├── kube-dns-autoscaler.deployment.yaml
│   ├── kube-dns-autoscaler.serviceaccounts.yaml
│   ├── kube-dns.deployment.yaml
│   ├── kube-dns.serviceaccounts.yaml
│   ├── kube-dns.service.yaml
│   ├── kubelet.service.yaml
│   ├── kube-prometheus-exporter-kube-controller-manager.service.yaml
│   ├── kube-prometheus-exporter-kube-dns.service.yaml
│   ├── kube-prometheus-exporter-kube-etcd.service.yaml
│   ├── kube-prometheus-exporter-kube-scheduler.service.yaml
│   ├── kube-proxy.serviceaccounts.yaml
│   ├── kube-state-backup-new.cronjob.yaml
│   ├── kube-sysctl.daemonset.yaml
│   ├── letsencrypt-prod.secret.yaml
│   ├── namespace-controller.serviceaccounts.yaml
│   ├── node-controller.serviceaccounts.yaml
│   ├── openvpn-ccd.configmap.yaml
│   ├── openvpn-crl.configmap.yaml
│   ├── openvpn.deployment.yaml
│   ├── openvpn-ingress.service.yaml
│   ├── openvpn-pki.secret.yaml
│   ├── openvpn-portmapping.configmap.yaml
│   ├── openvpn-settings.configmap.yaml
│   ├── persistent-volume-binder.serviceaccounts.yaml
│   ├── pod-garbage-collector.serviceaccounts.yaml
│   ├── replicaset-controller.serviceaccounts.yaml
│   ├── replication-controller.serviceaccounts.yaml
│   ├── resourcequota-controller.serviceaccounts.yaml
│   ├── route53-config.secret.yaml
│   ├── service-account-controller.serviceaccounts.yaml
│   ├── service-controller.serviceaccounts.yaml
│   ├── statefulset-controller.serviceaccounts.yaml
│   ├── sysctl-options.configmap.yaml
│   ├── tiller-deploy.deployment.yaml
│   ├── tiller-deploy.service.yaml
│   ├── tiller.serviceaccounts.yaml
│   └── ttl-controller.serviceaccounts.yaml
├── prd
│   ├── initdb.configmap.yaml
│   ├── example-app.deployment.yaml
│   ├── example-app.ingress.yaml
│   ├── example-app.secret.yaml
│   ├── example-app.service.yaml
│   ├── postgres-admin.secret.yaml
│   ├── postgresql.deployment.yaml
│   ├── postgresql.service.yaml
│   ├── postgres.secret.yaml
│   ├── prd.example.com.secret.yaml
│   ├── redis.service.yaml
│   └── redis-standalone.rc.yaml
└── staging
    ├── initdb.configmap.yaml
    ├── example-app.deployment.yaml
    ├── example-app.ingress.yaml
    ├── example-app.secret.yaml
    ├── example-app.service.yaml
    ├── postgres-admin.secret.yaml
    ├── postgresql.deployment.yaml
    ├── postgresql.service.yaml
    ├── postgres.secret.yaml
    ├── staging.example.com.secret.yaml
    ├── redis.service.yaml
    └── redis-standalone.rc.yaml

3 directories, 80 files
```

-------
This project is MIT licensed.

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
  * `RESOURCES` - **Required**. List of glob patterns `<+/-><resource type>:<namespace pattern>/<object pattern>`. The namespace is optional, e.g. `clusterrole:*`.
    Only namespace and object name can contain glob patterns, the resource type can't. **You can use either single or plural form for resource type but be consistent!**
    For secrets consider to use [git-crypt section](#git-crypt). Note that Tiller's config maps also can contain secrets.
    Example: `deployments:*/* -deployments/*test*/* +deployments/testimonial/* configmaps:*/* -configmaps:tiller/* namespaces:*` - All deployments which aren't contain 'test' except 'testimonial', all configmaps outside of namespace tiller and all namespace definitions.
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
│   ├── serviceaccounts.attachdetach-controller.yaml
│   ├── configmap.canal-config.yaml
│   ├── daemonset.canal.yaml
│   ├── serviceaccounts.canal.yaml
│   ├── serviceaccounts.certificate-controller.yaml
│   ├── serviceaccounts.cronjob-controller.yaml
│   ├── serviceaccounts.daemon-set-controller.yaml
│   ├── serviceaccounts.default.yaml
│   ├── serviceaccounts.deployment-controller.yaml
│   ├── serviceaccounts.disruption-controller.yaml
│   ├── deployment.dns-controller.yaml
│   ├── serviceaccounts.dns-controller.yaml
│   ├── serviceaccounts.endpoint-controller.yaml
│   ├── serviceaccounts.generic-garbage-collector.yaml
│   ├── serviceaccounts.horizontal-pod-autoscaler.yaml
│   ├── serviceaccounts.job-controller.yaml
│   ├── secret.kube-backup-gpg.yaml
│   ├── serviceaccounts.kube-backup.yaml
│   ├── secret.kube-backup-ssh.yaml
│   ├── configmap.kube-dns-autoscaler.yaml
│   ├── deployment.kube-dns-autoscaler.yaml
│   ├── serviceaccounts.kube-dns-autoscaler.yaml
│   ├── deployment.kube-dns.yaml
│   ├── serviceaccounts.kube-dns.yaml
│   ├── service.kube-dns.yaml
│   ├── service.kubelet.yaml
│   ├── service.kube-prometheus-exporter-kube-controller-manager.yaml
│   ├── service.kube-prometheus-exporter-kube-dns.yaml
│   ├── service.kube-prometheus-exporter-kube-etcd.yaml
│   ├── service.kube-prometheus-exporter-kube-scheduler.yaml
│   ├── serviceaccounts.kube-proxy.yaml
│   ├── cronjob.kube-state-backup-new.yaml
│   ├── daemonset.kube-sysctl.yaml
│   ├── secret.letsencrypt-prod.yaml
│   ├── serviceaccounts.namespace-controller.yaml
│   ├── serviceaccounts.node-controller.yaml
│   ├── configmap.openvpn-ccd.yaml
│   ├── configmap.openvpn-crl.yaml
│   ├── deployment.openvpn.yaml
│   ├── service.openvpn-ingress.yaml
│   ├── secret.openvpn-pki.yaml
│   ├── configmap.openvpn-portmapping.yaml
│   ├── configmap.openvpn-settings.yaml
│   ├── serviceaccounts.persistent-volume-binder.yaml
│   ├── serviceaccounts.pod-garbage-collector.yaml
│   ├── serviceaccounts.replicaset-controller.yaml
│   ├── serviceaccounts.replication-controller.yaml
│   ├── serviceaccounts.resourcequota-controller.yaml
│   ├── secret.route53-config.yaml
│   ├── serviceaccounts.service-account-controller.yaml
│   ├── serviceaccounts.service-controller.yaml
│   ├── serviceaccounts.statefulset-controller.yaml
│   ├── configmap.sysctl-options.yaml
│   ├── deployment.tiller-deploy.yaml
│   ├── service.tiller-deploy.yaml
│   ├── serviceaccounts.tiller.yaml
│   └── serviceaccounts.ttl-controller.yaml
├── prd
│   ├── configmap.initdb.yaml
│   ├── deployment.example-app.yaml
│   ├── ingress.example-app.yaml
│   ├── secret.example-app.yaml
│   ├── service.example-app.yaml
│   ├── secret.postgres-admin.yaml
│   ├── deployment.postgresql.yaml
│   ├── service.postgresql.yaml
│   ├── secret.postgres.yaml
│   ├── secret.prd.example.com.yaml
│   ├── service.redis.yaml
│   └── rc.redis-standalone.yaml
└── staging
    ├── configmap.initdb.yaml
    ├── deployment.example-app.yaml
    ├── ingress.example-app.yaml
    ├── secret.example-app.yaml
    ├── service.example-app.yaml
    ├── secret.postgres-admin.yaml
    ├── deployment.postgresql.yaml
    ├── service.postgresql.yaml
    ├── secret.postgres.yaml
    ├── secret.staging.example.com.yaml
    ├── service.redis.yaml
    └── rc.redis-standalone.yaml

3 directories, 80 files
```

-------
This project is MIT licensed.

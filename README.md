kube-backup
===========
[![Docker Repository on Quay](https://quay.io/repository/digidentity/kube-backup/status "Docker Repository on Quay")](https://quay.io/repository/digidentity/kube-backup)
[![Docker Repository on Docker Hub](https://img.shields.io/docker/automated/ptlange/kube-backup.svg "Docker Repository on Docker Hub")](https://hub.docker.com/r/ptlange/kube-backup/)

Quick 'n dirty kubernetes state backup script, designed to be ran as kubernetes Job. Think of it like [RANCID](http://www.shrubbery.net/rancid/) for kubernetes.

Props to @gianrubio for coming up with the idea.

Setup
-----
Use the [deployment example](cronjob.yaml) and deploy a kubernetes `CronJob` primitive in your kubernetes (1.5 and up) cluster ensuring backups of kubernetes resource definitions to your private git repo.

Define the following environment parameters:
  * `GIT_REPO` - GIT repo url. **Required**
  * `NAMESPACES` - List of namespaces to export. Default: all
  * `GLOBALRESOURCES` - List of global resource types to export. Default: `namespace`
  * `RESOURCETYPES` - List of resource types to export. Default: `ingress deployment configmap svc rc ds thirdpartyresource networkpolicy statefulset storageclass cronjob`. Notice that `Secret` objects are intentionally not exported by default.
  * `GIT_USERNAME` - Display name of git user. Default: `kube-backup`
  * `GIT_EMAIL` - Email address of git user. Default: `kube-backup@example.com`
  * `GIT_BRANCH` - Use a specific git branch . Default: `master`

Mount a configured ssh directory in `/backup/.ssh` with the following files:
  * `known_hosts` - Preloaded with SSH host key of `$GIT_REPO` host.
  * `id_rsa` - SSH private key of user allowed to push to `$GIT_REPO`.

Easiest way of doing this is:
```bash
ssh-keygen -f ./id_rsa
ssh-keyscan $YOUR_GIT_HOST > known_hosts

kubectl create secret generic kube-backup-ssh -n kube-system --from-file=id_rsa --from-file=known_hosts
```

Optional:
  * Modify the snapshot frequency in `spec.schedule` using the [cron format](https://en.wikipedia.org/wiki/Cron).
  * Modify the number of successful and failed finished jobs to retain in `spec.successfulJobsHistoryLimit` and `spec.failedJobsHistoryLimit`.

Result
------
All configured resources will be exported into a directory tree structure in `kind: List` YAML format following a `$namespace/$resourcetype.yaml` file structure.

```
.
├── default
│   ├── configmap.yaml
│   ├── cronjob.yaml
│   ├── deployment.yaml
│   ├── ds.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── petset.yaml
│   ├── rc.yaml
│   ├── statefulset.yaml
│   ├── storageclass.yaml
│   ├── svc.yaml
│   └── thirdpartyresource.yaml
├── kube-system
│   ├── configmap.yaml
│   ├── cronjob.yaml
│   ├── deployment.yaml
│   ├── ds.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── petset.yaml
│   ├── rc.yaml
│   ├── statefulset.yaml
│   ├── storageclass.yaml
│   ├── svc.yaml
│   └── thirdpartyresource.yaml
├── prd
│   ├── configmap.yaml
│   ├── cronjob.yaml
│   ├── deployment.yaml
│   ├── ds.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml
│   ├── petset.yaml
│   ├── rc.yaml
│   ├── statefulset.yaml
│   ├── storageclass.yaml
│   ├── svc.yaml
│   └── thirdpartyresource.yaml
└── staging
    ├── configmap.yaml
    ├── cronjob.yaml
    ├── deployment.yaml
    ├── ds.yaml
    ├── ingress.yaml
    ├── networkpolicy.yaml
    ├── petset.yaml
    ├── rc.yaml
    ├── statefulset.yaml
    ├── storageclass.yaml
    ├── svc.yaml
    └── thirdpartyresource.yaml

4 directories, 48 files
```

Caveat
------
This is using a kubernetes alpha feature ([cronjobs](https://kubernetes.io/docs/user-guide/jobs/#handling-pod-and-container-failures)) and hasn't been tested for idempotency/concurrent behaviour.  See the cronjob [documentation](https://kubernetes.io/docs/user-guide/cron-jobs/) for details.

If your kubernetes cluster runs under version 1.5 or less, `spec.successfulJobsHistoryLimit` and `spec.failedJobsHistoryLimit` will be ignored as they've been introduced in version 1.6. In this case, running an export every 10 minutes will quickly run up your Job (and therefor Pod) count, causing a linear increase in master server load. A fix for this is to deploy a [blunt instrument](job-cleanup.yaml) to clean the old kube-backup jobs.

License
-------
This project is MIT licensed.

kube-backup
===========
Quick 'n dirty kubernetes state backup script, designed to be ran as kubernetes Job. Think of it like [RANCID](http://www.shrubbery.net/rancid/) for kubernetes.

Props to @gianrubio for coming up with the idea.


Setup
-----
Deployment example used the kubernetes [`CronJob` primitive](cronjob.yaml) and will push a backup to git every 10 minutes.

Define the following environment parameters:
  * `GIT_REPO` - GIT repo url. **Required**
  * `NAMESPACES` - List of namespaces to export. Default: all
  * `RESOURCE_TYPES` - List of resource types to export. Default: `ingress deployment configmap svc rc secrets ds thirdpartyresource networkpolicy statefulset storageclass cronjob`
  * `GIT_USERNAME` - Display name of git user. Default: `kube-backup`
  * `GIT_EMAIL` - Email address of git user. Default: `kube-backup@example.com`

Mount a configured ssh directory in `/backup/.ssh` with the following files:
  * `known_hosts` - Preloaded with SSH host key of `$GIT_REPO` host.
  * `id_rsa` - SSH private key of user allowed to push to `$GIT_REPO`

Easiest way of doing this is:
```bash
mkdir ssh_secret
cd ssh_secret
ssh-keygen -f ./id_rsa
ssh-keyscan $YOUR_GIT_HOST > known_hosts

kubectl create secret generic kube-backup-ssh -n kube-system --from-file=id_rsa --from-file=known_hosts
```

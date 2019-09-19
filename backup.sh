#!/bin/bash
mkdir -p /tmp/backup
DRY_RUN=true GIT_REPO_PATH=/tmp/backup ./entrypoint.sh

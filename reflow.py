#!/usr/bin/env python

import sys
import yaml
import json

data = json.load(sys.stdin)

# we don't want to preserve 'clusterIP: <ip address>' because in
# a restore-from-scratch situation the value will be bogus, but
# if the value is "None", that indicates a headless service and
# we _do_ want to preserve that.
if 'spec' in data:
    if 'clusterIP' in data['spec']:
        if data['spec']['clusterIP'] != "None":
            del(data['spec']['clusterIP'])

yaml.safe_dump(data, sys.stdout, explicit_start=True, default_flow_style=False)

#!/bin/bash -x

/usr/bin/podman exec -i rt5 bash -c "(cd /attachments/; tar -czf - *)" > /store/backups/attachments-`date +%s`.tgz


#!/bin/bash

QUEUE=$1
ACTION=$2

logger "Processing RT message Queue: ${QUEUE} Action: ${ACTION}"
cat |podman exec -i rt5 bash -c "cat - | /opt/rt5/bin/rt-mailgate --no-verify-ssl --queue ${QUEUE} --action ${ACTION} --url http://localhost:8080/"

exit 0


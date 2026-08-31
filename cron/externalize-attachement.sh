#!/bin/bash
# Externalize attachments via RT CLI in the rt5 quadlet container.
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

/usr/bin/podman exec rt5 /opt/rt5/sbin/rt-externalize-attachments

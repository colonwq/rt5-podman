# How to build Request Tracker 5 and run as a quadlet container

This repository contains the configuration files and scripts necessary to build a Request Tracker container, run it as a quadlet service and integrate with an existing data center. 

The complete documenation is in the blog post XXXX

## Repo Contents

- [config](config): Runtime configuration files
- [cron](cron): Routine maintenance cron jobs
- [host_config](host_config): postfix config files for the quadlet host server
- [mailhub_config](mailhub_config): Postfix config files for the mailhub
- [podman](podman): Container file
- [quadlet](quadlet): Quadlet files
- [selinux](selinux): Selinux rules

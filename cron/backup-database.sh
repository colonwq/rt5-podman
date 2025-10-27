#!/bin/bash -x

/usr/bin/podman exec -i rt5 bash -c "( mysqldump -u rt_user -prt_pass -h db.example.com --default-character-set=utf8mb4 rt5 --tables sessions --no-data --single-transaction; mysqldump -u rt_user -prt_pass -h db.example.com --default-character-set=utf8mb4 rt5 --ignore-table rt5.sessions --single-transaction )"  | gzip > /store/backups/rt-`date +%s`.sql.gz


# System Maintenance Cron Jobs

Typically, three routine tasks needs to be performed on RT5 application. The following example scripts can be adapted for local needs. 


- externalize-attachement.sh: Extract ticket attachments from the database and save them to the attachment directory
- backup-attachments.sh: Backup the attachments directory
- backup-database.sh: Backup the RT database contents

Example schedule:
```
10 12 * * * /home/colonwq/bin/externalize-attachement.sh
10 15 * * * /home/colonwq/bin/backup-attachments.sh
10 15 * * * /home/colonwq/bin/backup-database.sh
```
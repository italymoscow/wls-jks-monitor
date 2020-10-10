# wls-jks-monitor
The script can be used for monitoring validity of the certificates in the Java Keystore. It parses the given Java Keystores and sends an email notification if there are any certificates that either have already expired or will expire in less than \[THRESHOLD_DAYS]. The script can be copied to the server (e.g. to `~/jks_monitor`) and a corresponding cron job can be set up to start the script execution for example once a day.

Before installation, the following upper part of the script needs to be configured for the environment it will be used in:

Configurable part of JKSMonitor.sh:
```bash
#!/bin/bash

# Environment
readonly ENV="QA"

declare -a keystore_paths
declare -a keystore_passes

# List of keystore_paths and corresponding keystore_passes (use the same index)
keystore_paths[0]="/[keystore1_dir]/[keystore1_name]"
keystore_passes[0]="[keystore1_pass]"

keystore_paths[1]="/[keystore2_dir]/[keystore2_name]"
keystore_passes[1]="[keystore2_pass]"

# A certificate expiring in THRESHOLD_DAYS days will result in a warning
readonly THRESHOLD_DAYS=7

# Comma separated list of emails
readonly  MAIL_TO="mailto1@host.com,mailto2@host.com"

# ----------- Do not make changes after this line -----------
```
`ENV` is the alias of the environment where the host is running, e.g. `PROD`, `QA`, `TEST`, etc.

`keystore_paths` is an array containing one or several paths to JKS. It must be indexed.

`keystore_passes` is an array containing the passwords to the corresponding JKS (by index).

`MAIL_TO` contains a comma separated list of email addresses for the notification.

Once the script is reconfigured, copied on server and made executable (`chmod +x ~/JKSMonitor.sh`), a cron job can be created to schedule execution of the script at 12:00 every working day:
```
crontab -e
0 12 * * 1-5 ~/shell_scripts/JKSMonitor.sh
```

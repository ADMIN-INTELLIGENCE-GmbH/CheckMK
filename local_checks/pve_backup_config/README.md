The script `check_pve_backup_config_cron.sh` needs to be set put into the following folder: `/usr/lib/check_mk_agent/` and then set up as a cronjob, e.g.:

```
* */10 * * * /usr/lib/check_mk_agent/check_pve_config_backup_cron.sh
```

---
The script `pve_backup_config_check` needs to be places under `/usr/lib/check_mk_agent/local`.
# General
A script to easily deploy the checkmk agent on Ubuntu machines.

# Requirements
- An existing installation of CheckMK

# Information
## Changelog
```
v0.1: Initial Release
v0.2: Change Menu
v0.3: Add Hetzner Workflow
v0.4: install default plugins (apt, netstat)
v0.5: autoinstaller for MySQL, Fail2ban, Docker, PostgreSQL
v0.6: change to autoinstaller only, added firewall check for ufw or iptables
```


## TODO
- [ ] check for running processes and install plugins accordingly
  - [x] MySQL
      - [x] Password random + check if user already exists
  - [x] Fail2ban
  - [x] Docker
  - [ ] Apache
  - [ ] NGINX
  - [x] PostgreSQL
- [x] check if iptables or ufw is used and create commands for each type of firewall
- [ ] Rsnapshot
  - [x] simple check (OK / CRIT)
  - [ ] extended check (+ Timestamps)

# Usage
TODO

## HowTo
TODO

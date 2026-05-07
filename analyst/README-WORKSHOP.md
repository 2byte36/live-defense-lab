# Analyst Container Guide

You are inside an isolated Docker analyst container. This shell is for log review and workshop analysis only.

## What to Inspect

```bash
ls -R /logs
tail -f /logs/web/access.log
tail -f /logs/web/app.log
less /logs/suricata/fast.log
less /logs/suricata/eve.json
```

The target web app is reachable from this container by service name:

```bash
curl -s http://helpdesk:5000/health
```

## Your Answer Format

Prepare a short answer for the instructor:

```text
Suspected attacker IP:
Evidence:
Attack type:
Recommended mitigation:
```

The mitigation decision should be an IP block recommendation, but you do not run host firewall commands from this container.

## Controlled Mitigation

After the instructor approves your finding, you may run the workshop mitigation wrappers:

```bash
sudo /usr/local/bin/workshop-block-ip <attacker-ip>
sudo /usr/local/bin/workshop-list-blocked
sudo /usr/local/bin/workshop-unblock-ip <attacker-ip>
```

These commands only request web-app blocks through the workshop helper. They do not give you Docker access or general firewall access.

## Boundaries

- You only SSH into this analyst container.
- `/logs` is mounted read-only.
- The Docker socket is not mounted.
- You cannot run host `iptables` from here.
- `sudo` is limited to the three workshop mitigation wrapper commands.

## Useful Commands

```bash
grep -i "union\\|select\\|--" /logs/web/access.log
grep -i "tools/base64\\|;\\|whoami\\| id " /logs/web/access.log /logs/web/app.log
grep -i "download" /logs/web/access.log
awk 'index($7, "/search") {print $1, $4, $5, $6, $7, $9}' /logs/web/access.log
awk 'index($7, "/tools/base64") {print $1, $4, $5, $6, $7, $9}' /logs/web/access.log
awk 'index($7, "/download") {print $1, $4, $5, $6, $7, $9}' /logs/web/access.log
```

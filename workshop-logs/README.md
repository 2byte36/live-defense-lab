# Workshop Logs

This directory contains one isolated log tree per group. Each `helpdesk-groupN` container writes to `workshop-logs/groupN`, and each matching `groupN-analyst` container mounts only that directory as `/logs:ro`.

Implemented now:

- `groupN/web/access.log`: Apache/Nginx combined-style plaintext written by that group's Flask app for every HTTP request.
- `groupN/web/app.log`: plaintext `key=value` application events such as logins, searches, ticket views, tool usage, and downloads.

Example access line:

```text
198.51.100.23 - - [07/May/2026:21:00:12 +0000] "GET /search?q=test HTTP/1.1" 200 512 "-" "curl/8.0"
```

Expected later integration:

- `groupN/suricata/fast.log`: placeholder for Suricata alert output.
- `groupN/suricata/eve.json`: placeholder for Suricata EVE JSON output.

Suricata is not started by the current Compose stack. Add it later only if the VPS has enough CPU and memory headroom.

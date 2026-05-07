# Live Defense Workshop Runbook

This lab runs one vulnerable Flask helpdesk target, one benign traffic generator, and four isolated analyst SSH containers per VPS. Participants SSH into analyst containers only; they do not SSH into the VPS host.

The target app is intentionally vulnerable and must only run in an isolated training environment.

## Architecture

- `helpdesk`: vulnerable Flask app on host port `5000`, SQLite database in a Docker volume, web logs written to `./workshop-logs`.
- `benign-traffic`: lightweight Python traffic generator that creates low-rate background requests to normal app paths.
- `mitigation-helper`: no published ports; listens on a root-only Unix socket shared with analyst containers and applies approved web-only `DOCKER-USER` rules.
- `group1-analyst` through `group4-analyst`: SSH containers on host ports `2201` through `2204`.
- `./workshop-logs:/logs`: mounted read-write in `helpdesk`, mounted read-only in analyst containers.
- No Docker socket is mounted into analyst containers.
- No privileged analyst containers.
- No host firewall control inside analyst containers.

## Build And Start

```bash
docker compose up --build -d
docker compose ps
./scripts/check-lab.sh
```

Open the target app:

```text
http://<vps-ip>:5000
```

To customize published ports, copy `.env.example` to `.env` and edit `HELPDESK_PORT` or `GROUP*_SSH_PORT` before starting Compose.

Default app accounts:

| Username | Password |
| --- | --- |
| alice | password123 |
| bob | helpdesk |
| carol | reports |
| admin | admin123 |

## Participant SSH Access

Default analyst credentials:

```text
username: analyst
password: analyst123
```

Examples:

```bash
ssh analyst@<vps-ip> -p 2201
ssh analyst@<vps-ip> -p 2202
ssh analyst@<vps-ip> -p 2203
ssh analyst@<vps-ip> -p 2204
```

Suggested mapping:

| Group | Container | SSH Port |
| --- | --- | --- |
| Group 1 | group1-analyst | 2201 |
| Group 2 | group2-analyst | 2202 |
| Group 3 | group3-analyst | 2203 |
| Group 4 | group4-analyst | 2204 |

For 8 groups across 2 VPS, run this same stack on each VPS and assign four groups per VPS.

## Participant Log Analysis

Inside an analyst container:

```bash
ls -R /logs
tail -f /logs/web/access.log
tail -f /logs/web/app.log
less /logs/suricata/fast.log
less /logs/suricata/eve.json
```

The web access log uses classic combined-style plaintext:

```text
198.51.100.23 - - [07/May/2026:21:00:12 +0000] "GET /search?q=test HTTP/1.1" 200 512 "-" "curl/8.0"
```

Useful searches:

```bash
grep -i "union\|select\|--\| or " /logs/web/access.log
grep -i "tools/base64\|whoami\| id \|;" /logs/web/access.log /logs/web/app.log
grep -i "download.*\.\.\|/etc/passwd\|app.py" /logs/web/access.log /logs/web/app.log
awk 'index($7, "/search") {print $1, $4, $5, $6, $7, $9}' /logs/web/access.log
awk 'index($7, "/tools/base64") {print $1, $4, $5, $6, $7, $9}' /logs/web/access.log
awk 'index($7, "/download") {print $1, $4, $5, $6, $7, $9}' /logs/web/access.log
```

Target reachability from analyst containers:

```bash
curl -s http://helpdesk:5000/health
```

## Participant Answer Format

Each group should answer:

```text
Suspected attacker IP:
Evidence/log lines:
Attack type:
Mitigation decision:
```

Mitigation should be a recommendation such as:

```text
Block <IP> with iptables because the access log shows SQL injection attempts against /search.
```

Participants do not run the firewall command.

## Instructor Benign Traffic

The `benign-traffic` container starts with Compose and periodically accesses:

```text
/dashboard
/api/tickets
/health
/profile
/api/stats
```

It uses random delays and user agents to create realistic background noise without meaningful CPU or memory load.

Create a normal authenticated session:

```bash
curl -c cookies.txt -b cookies.txt \
  -d "username=alice&password=password123" \
  http://<vps-ip>:5000/login
```

Normal requests:

```bash
curl -b cookies.txt http://<vps-ip>:5000/dashboard
curl -b cookies.txt http://<vps-ip>:5000/tickets
curl -b cookies.txt http://<vps-ip>:5000/api/tickets
curl -b cookies.txt http://<vps-ip>:5000/api/users/me
curl -b cookies.txt -X POST \
  -H "Content-Type: application/json" \
  -d '{"rating":"good","comment":"Queue looks normal"}' \
  http://<vps-ip>:5000/api/feedback
```

## Instructor Malicious Traffic

Prefer running demo traffic from an instructor or helper machine so the real source IP appears in `access.log`.

Reproducible demo scripts:

```bash
TARGET_URL=http://<vps-ip>:5000 ./scripts/run-sqli-demo.sh
TARGET_URL=http://<vps-ip>:5000 ./scripts/run-cmdi-demo.sh
TARGET_URL=http://<vps-ip>:5000 ./scripts/run-traversal-demo.sh
TARGET_URL=http://<vps-ip>:5000 ./scripts/demo-attack-sequence.sh
```

Manual examples use a separate cookie jar for the attacker session:

```bash
curl -c attacker-cookies.txt -b attacker-cookies.txt \
  -d "username=alice&password=password123" \
  http://<vps-ip>:5000/login
```

SQL injection:

```bash
curl -b attacker-cookies.txt \
  "http://<vps-ip>:5000/search?q=%27%20UNION%20SELECT%20id%2Cusername%7C%7C%27%3A%27%7C%7Cpassword%2Crole%2Cemail%2Cusername%20FROM%20users--"
```

Command injection:

```bash
curl -b attacker-cookies.txt \
  -X POST --data-urlencode "text=hello; id; #" \
  http://<vps-ip>:5000/tools/base64
```

Path traversal:

```bash
curl -b attacker-cookies.txt \
  "http://<vps-ip>:5000/download?file=../app.py"
```

## Mitigation Flow

Participants can trigger controlled mitigation from inside their analyst containers after the instructor approves the finding. They do not receive general root access, Docker socket access, or unrestricted firewall access.

Block an IP:

```bash
sudo /usr/local/bin/workshop-block-ip 198.51.100.23
```

The block only targets traffic forwarded by Docker to the vulnerable web app. It does not add `INPUT` rules, so it should not block SSH or other host services.

List current workshop web DROP rules:

```bash
sudo /usr/local/bin/workshop-list-blocked
```

Unblock an IP:

```bash
sudo /usr/local/bin/workshop-unblock-ip 198.51.100.23
```

The analyst container sudoers rule allows only these exact wrapper commands:

```sudoers
analyst ALL=(root) NOPASSWD: /usr/local/bin/workshop-block-ip, /usr/local/bin/workshop-unblock-ip, /usr/local/bin/workshop-list-blocked
```

The wrapper validates IPv4 input, connects to the root-only mitigation Unix socket, and the helper validates again before inserting a commented rule into Docker's `DOCKER-USER` chain:

```bash
iptables -I DOCKER-USER 1 -s <IP> -p tcp --dport ${WEB_PORT:-5000} -m comment --comment live-defense-workshop-web -j DROP
```

Docker usually evaluates `DOCKER-USER` after destination NAT. In this lab the published port and container port are both `5000`, so the rule matches port `5000` in `DOCKER-USER`. If you publish the app on a different host port, test from an off-host client and set `WEB_PORT` to the destination port visible in `DOCKER-USER`.

The equivalent host-side scripts remain available to instructors on the VPS:

```bash
sudo ./scripts/block-ip.sh 198.51.100.23
sudo ./scripts/list-blocked.sh
sudo iptables -L DOCKER-USER -n -v --line-numbers
sudo ./scripts/unblock-ip.sh 198.51.100.23
```

Do not mount host firewall controls or Docker socket into analyst containers.

## Reset The Lab

Use the reset helper from the VPS host:

```bash
./scripts/reset-lab.sh
```

It removes workshop web block rules from `DOCKER-USER`, removes legacy `LIVE_DEFENSE_BLOCK` rules from older script versions, truncates or rotates logs, recreates the SQLite Docker volume, rebuilds images if needed, and restarts containers cleanly. Use `RESET_LOG_MODE=rotate ./scripts/reset-lab.sh` to keep timestamped copies of previous logs.

## Readiness Checks

```bash
./scripts/check-lab.sh
```

This checks Compose validity, running containers, SSH ports, log files, read-only `/logs` mounts, target reachability, and SSH login if `sshpass` is installed.

## SSH Stress Test

Install `sshpass` on the VPS if needed:

```bash
sudo apt-get update && sudo apt-get install -y sshpass
```

Run around 16 concurrent SSH sessions:

```bash
./scripts/ssh-stress-test.sh
```

If password automation is unavailable, use a temporary test key and set:

```bash
SSH_KEY=/path/to/test_key ./scripts/ssh-stress-test.sh
```

Observe resource usage:

```bash
./scripts/monitor-resources.sh
```

You can change concurrency:

```bash
SESSIONS_PER_GROUP=6 ./scripts/ssh-stress-test.sh
```

## Known Limitations

- Suricata is not implemented by this Compose stack. The Suricata log files are placeholders for later IDS integration.
- The Flask development server is used for simplicity; this is acceptable for an isolated workshop target, not production.
- App login passwords and workshop SSH passwords are intentionally simple for training logistics.
- Source IPs come from the real TCP peer observed by Flask. Run attacks from instructor/helper machines when distinct attacker attribution matters.
- Workshop mitigation rules are scoped to Docker-forwarded web traffic in `DOCKER-USER`. Do not add broad `INPUT` drops for participant exercises.
- Keep the stack lightweight. Do not add ELK, Kubernetes, a heavy SIEM, or other services unless you have measured spare CPU and memory headroom.

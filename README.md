# Lightweight Vulnerable Helpdesk

Small Flask and SQLite helpdesk portal for controlled cybersecurity defense workshops. It intentionally includes SQL injection, command injection, and path traversal examples so participants can practice live attack observation, log analysis, and detection engineering.

Do not expose this app to the public internet outside a controlled lab.

For the multi-group analyst SSH container workflow, use [WORKSHOP_RUNBOOK.md](WORKSHOP_RUNBOOK.md).

## Features

- Login, dashboard, ticket queue, ticket detail, search, profile, and internal tools pages.
- SQLite seed data for users, customers, tickets, audit logs, and invoices.
- Normal-looking API traffic from browser polling and the lightweight `benign-traffic` container.
- Apache/Nginx combined-style plaintext request logs written to stdout and to `workshop-logs/web/access.log`.
- Application events written to the `audit_logs` table and to plaintext `key=value` lines in `workshop-logs/web/app.log`.
- Four isolated analyst SSH containers with read-only access to `workshop-logs`.
- `GROUP_NAME` environment variable displayed in the UI.

## Run With Docker

```bash
docker compose up --build
```

Open `http://localhost:5000`.

The app listens on `0.0.0.0:5000`. SQLite is initialized automatically if the database file is missing. Analyst SSH containers listen on host ports `2201` through `2204`. The `benign-traffic` container periodically signs in and visits `/dashboard`, `/api/tickets`, `/health`, `/profile`, and `/api/stats` with random delays and user agents.

To customize published ports, copy `.env.example` to `.env` and edit the values before running Compose.

Default accounts:

| Username | Password |
| --- | --- |
| alice | password123 |
| bob | helpdesk |
| carol | reports |
| admin | admin123 |

To watch traffic logs:

```bash
docker logs -f live-defense-helpdesk-1
tail -f workshop-logs/web/access.log
tail -f workshop-logs/web/app.log
```

Access log format:

```text
198.51.100.23 - - [07/May/2026:21:00:12 +0000] "GET /search?q=test HTTP/1.1" 200 512 "-" "curl/8.0"
```

Beginner-friendly examples:

```bash
grep -i "union\|select\|--" workshop-logs/web/access.log
awk 'index($7, "/search") {print $1, $4, $5, $6, $7, $9}' workshop-logs/web/access.log
less workshop-logs/web/app.log
```

If your Compose project name differs, run `docker compose ps` to confirm the container name.

To SSH into an analyst container:

```bash
ssh analyst@localhost -p 2201
```

Default analyst password: `analyst123`.

## Run Locally

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
GROUP_NAME="Local Lab" python app.py
```

## Example Benign Requests

```bash
curl -i http://localhost:5000/health

curl -c cookies.txt -b cookies.txt \
  -d "username=alice&password=password123" \
  http://localhost:5000/login

curl -b cookies.txt http://localhost:5000/dashboard
curl -b cookies.txt http://localhost:5000/tickets
curl -b cookies.txt http://localhost:5000/api/tickets
curl -b cookies.txt http://localhost:5000/api/users/me

curl -b cookies.txt -X POST \
  -H "Content-Type: application/json" \
  -d '{"rating":"good","comment":"Queue looks normal"}' \
  http://localhost:5000/api/feedback

curl -b cookies.txt -X POST \
  -d "customer_id=1&priority=Medium&title=Printer access request&description=Customer needs printer queue access restored." \
  http://localhost:5000/tickets
```

## Example Attack Requests

These examples require an authenticated session in `cookies.txt`.

SQL injection through `/search?q=`:

```bash
curl -b cookies.txt "http://localhost:5000/search?q=%27%20UNION%20SELECT%20id%2Cusername%7C%7C%27%3A%27%7C%7Cpassword%2Crole%2Cemail%2Cusername%20FROM%20users--"
```

Command injection through the fake Base64 Encoder:

```bash
curl -b cookies.txt -X POST \
  --data-urlencode "text=hello; id; #" \
  http://localhost:5000/tools/base64
```

Path traversal through `/download?file=`:

```bash
curl -b cookies.txt "http://localhost:5000/download?file=../app.py"
curl -b cookies.txt "http://localhost:5000/download?file=/etc/passwd"
```

Instructor helper scripts provide reproducible live demos:

```bash
TARGET_URL=http://<vps-ip>:5000 ./scripts/run-sqli-demo.sh
TARGET_URL=http://<vps-ip>:5000 ./scripts/run-cmdi-demo.sh
TARGET_URL=http://<vps-ip>:5000 ./scripts/run-traversal-demo.sh
TARGET_URL=http://<vps-ip>:5000 ./scripts/demo-attack-sequence.sh
```

Run these from the instructor or helper machine whose real source IP should appear in `access.log`.

## Vulnerable Sections

The intentionally unsafe sections are marked in `app.py` comments:

- `/search`: SQL query string concatenation.
- `/tools/base64`: `subprocess.run(..., shell=True)` with user input.
- `/download`: file path joined and opened without validation.

Do not fix these in the workshop target unless you are creating a separate remediation exercise.

## Suricata Rule Ideas

Tune SIDs, networks, ports, and thresholds for your lab.

Possible SQL injection detection:

```suricata
alert http any any -> $HOME_NET 5000 (msg:"LAB helpdesk possible SQL injection in search"; flow:to_server,established; http.uri; content:"/search"; nocase; http.uri; pcre:"/(\%27|'|--|\bUNION\b|\bSELECT\b|\bOR\b\s+\d+=\d+)/Ui"; classtype:web-application-attack; sid:1000001; rev:1;)
```

Possible command injection detection:

```suricata
alert http any any -> $HOME_NET 5000 (msg:"LAB helpdesk possible command injection in base64 tool"; flow:to_server,established; http.uri; content:"/tools/base64"; nocase; http.request_body; pcre:"/(;|%3b|&&|%26%26|\||%7c|`|\$\(|\b(id|whoami|cat|curl|wget|bash|sh)\b)/Ui"; classtype:web-application-attack; sid:1000002; rev:1;)
```

Possible path traversal detection:

```suricata
alert http any any -> $HOME_NET 5000 (msg:"LAB helpdesk possible path traversal"; flow:to_server,established; http.uri; content:"/download"; nocase; http.uri; pcre:"/(\.\.\/|\.\.%2f|%2e%2e%2f|\/etc\/passwd)/Ui"; classtype:web-application-attack; sid:1000003; rev:1;)
```

Use the app's combined-style access log and `audit_logs` table alongside IDS alerts so participants can compare network, request, and application-level evidence.

## Operations Helpers

Reset the lab, reseed SQLite, clear workshop firewall blocks, and restart containers:

```bash
./scripts/reset-lab.sh
```

Monitor VPS stability during live testing:

```bash
./scripts/monitor-resources.sh
```

Workshop web-only mitigation:

```bash
sudo /usr/local/bin/workshop-block-ip <attacker-ip>
sudo /usr/local/bin/workshop-list-blocked
sudo /usr/local/bin/workshop-unblock-ip <attacker-ip>
```

Participants run those commands inside analyst containers. Sudo is limited to those three wrappers only; they call a tiny mitigation helper over a root-only Unix socket. The helper uses Docker's `DOCKER-USER` chain with comment `live-defense-workshop-web` and default `WEB_PORT=5000`. It does not add `INPUT` DROP rules, so SSH to the VPS host remains available.

The same host-side scripts remain available to instructors on the VPS:

```bash
sudo ./scripts/block-ip.sh <attacker-ip>
sudo ./scripts/list-blocked.sh
sudo ./scripts/unblock-ip.sh <attacker-ip>
```

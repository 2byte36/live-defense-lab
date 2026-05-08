import os
import sqlite3
import subprocess
from datetime import datetime, timezone
from functools import wraps
from pathlib import Path

from flask import (
    Flask,
    Response,
    abort,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("DATABASE_PATH", BASE_DIR / "helpdesk.db"))
DOWNLOAD_DIR = BASE_DIR / "downloads"
GROUP_NAME = os.environ.get("GROUP_NAME", "Workshop Group")
LOG_DIR = Path(os.environ.get("LOG_DIR", BASE_DIR / "workshop-logs"))
ACCESS_LOG_PATH = Path(os.environ.get("ACCESS_LOG_PATH", LOG_DIR / "web" / "access.log"))
APP_LOG_PATH = Path(os.environ.get("APP_LOG_PATH", LOG_DIR / "web" / "app.log"))

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "workshop-dev-secret-change-me")


def db_connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def get_db():
    if "db" not in g:
        g.db = db_connect()
    return g.db


@app.teardown_appcontext
def close_db(_error=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    with db_connect() as db:
        db.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL,
                full_name TEXT NOT NULL,
                email TEXT NOT NULL,
                role TEXT NOT NULL,
                department TEXT NOT NULL,
                last_login TEXT
            );

            CREATE TABLE IF NOT EXISTS customers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                company TEXT NOT NULL,
                tier TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tickets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                customer_id INTEGER,
                assigned_to INTEGER,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                status TEXT NOT NULL,
                priority TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(customer_id) REFERENCES customers(id),
                FOREIGN KEY(assigned_to) REFERENCES users(id)
            );

            CREATE TABLE IF NOT EXISTS audit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                username TEXT,
                event_type TEXT NOT NULL,
                details TEXT,
                ip_address TEXT,
                user_agent TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS invoices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                customer_id INTEGER,
                invoice_number TEXT NOT NULL,
                amount_cents INTEGER NOT NULL,
                status TEXT NOT NULL,
                issued_at TEXT NOT NULL,
                notes TEXT,
                FOREIGN KEY(customer_id) REFERENCES customers(id)
            );
            """
        )

        user_count = db.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        if user_count:
            return

        now = utc_now()
        db.executemany(
            """
            INSERT INTO users (username, password, full_name, email, role, department, last_login)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                ("alice", "password123", "Alice Nguyen", "alice@internal.example", "Analyst", "Support", now),
                ("bob", "helpdesk", "Bob Prasetyo", "bob@internal.example", "Agent", "Support", now),
                ("carol", "reports", "Carol Smith", "carol@internal.example", "Manager", "Operations", now),
                ("admin", "admin123", "Admin User", "admin@internal.example", "Administrator", "IT", now),
            ],
        )
        db.executemany(
            """
            INSERT INTO customers (name, email, company, tier)
            VALUES (?, ?, ?, ?)
            """,
            [
                ("Nadia Putri", "nadia.putri@example.net", "Garuda Retail", "Gold"),
                ("Rizky Hartono", "rizky.h@example.net", "Merapi Finance", "Platinum"),
                ("Maya Johnson", "maya.j@example.net", "Northwind Logistics", "Silver"),
                ("Tono Wijaya", "tono.w@example.net", "Jakarta Health", "Gold"),
                ("Sarah Lim", "sarah.lim@example.net", "Pacific Manufacturing", "Bronze"),
            ],
        )
        db.executemany(
            """
            INSERT INTO tickets
                (customer_id, assigned_to, title, description, status, priority, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (1, 1, "VPN disconnects during invoice upload", "Customer reports VPN drops when attaching invoice PDFs over 10 MB.", "Open", "High", now, now),
                (2, 2, "Payment confirmation email delayed", "Finance portal shows payment complete but notification email arrived four hours late.", "In Progress", "Medium", now, now),
                (3, 1, "Password reset loop", "User receives reset link but browser returns to the login page after submitting a new password.", "Open", "Medium", now, now),
                (4, 3, "Monthly report export missing rows", "Operations export for April appears to omit closed escalations from the CSV.", "Pending", "High", now, now),
                (5, 2, "Customer profile phone number stale", "Account team requested a contact update after the latest onboarding call.", "Closed", "Low", now, now),
                (1, 3, "SLA dashboard card count mismatch", "Dashboard total differs from the support queue count by three tickets.", "In Progress", "Low", now, now),
            ],
        )
        db.executemany(
            """
            INSERT INTO invoices (customer_id, invoice_number, amount_cents, status, issued_at, notes)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                (1, "INV-2026-0417", 1275000, "Paid", "2026-04-17", "Annual support renewal"),
                (2, "INV-2026-0421", 4820000, "Pending", "2026-04-21", "Enterprise incident response retainer"),
                (3, "INV-2026-0424", 915000, "Paid", "2026-04-24", "Log analysis package"),
                (4, "INV-2026-0501", 2230000, "Overdue", "2026-05-01", "Helpdesk seat expansion"),
            ],
        )
        db.executemany(
            """
            INSERT INTO audit_logs (user_id, username, event_type, details, ip_address, user_agent, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (1, "alice", "ticket.view", "Opened ticket #1", "10.10.20.15", "Mozilla/5.0", now),
                (2, "bob", "ticket.update", "Changed ticket #2 status to In Progress", "10.10.20.18", "Mozilla/5.0", now),
                (3, "carol", "report.export", "Exported operations ticket summary", "10.10.20.21", "Mozilla/5.0", now),
                (None, "system", "health.check", "Background monitor reported healthy", "127.0.0.1", "curl/8.0", now),
            ],
        )


def utc_now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def init_log_files():
    for log_path in (ACCESS_LOG_PATH, APP_LOG_PATH):
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.touch(exist_ok=True)


def log_escape(value, default="-"):
    text = default if value is None or value == "" else str(value)
    escaped = []
    for char in text:
        if char == "\\":
            escaped.append("\\\\")
        elif char == '"':
            escaped.append('\\"')
        elif ord(char) < 32 or ord(char) == 127:
            escaped.append("?")
        else:
            escaped.append(char)
    return "".join(escaped)


def append_log_line(log_path, line):
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(
            f'{utc_now()} event=log.write_error path="{log_escape(log_path)}" error="{log_escape(exc)}"',
            flush=True,
        )


def client_ip():
    return request.remote_addr or "-"


def combined_log_time():
    return datetime.now().astimezone().strftime("%d/%b/%Y:%H:%M:%S %z")


def request_target():
    raw_uri = request.environ.get("RAW_URI") or request.environ.get("REQUEST_URI")
    if raw_uri:
        return raw_uri

    query_string = request.query_string.decode("utf-8", errors="replace")
    if query_string:
        return f"{request.path}?{query_string}"
    return request.path or "/"


def response_size(response):
    size = response.calculate_content_length()
    if size is not None:
        return str(size)

    header_size = response.headers.get("Content-Length")
    if header_size and header_size.isdigit():
        return header_size

    return "-"


def app_event_line(created_at, event_type, username, ip_address, user_agent, details):
    return (
        f'{created_at} event={event_type} user={username} ip={ip_address} '
        f'ua="{log_escape(user_agent)}" details="{log_escape(details, default="")}"'
    )


def current_user():
    user_id = session.get("user_id")
    if not user_id:
        return None
    return get_db().execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def write_audit_event(event_type, details="", user=None):
    user = user if user is not None else current_user()
    created_at = utc_now()
    ip_address = client_ip()
    user_agent = request.headers.get("User-Agent", "-")
    db = get_db()
    db.execute(
        """
        INSERT INTO audit_logs (user_id, username, event_type, details, ip_address, user_agent, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            user["id"] if user else None,
            user["username"] if user else "anonymous",
            event_type,
            details,
            ip_address,
            user_agent,
            created_at,
        ),
    )
    db.commit()
    append_log_line(
        APP_LOG_PATH,
        app_event_line(
            created_at,
            event_type,
            user["username"] if user else "anonymous",
            ip_address,
            user_agent,
            details,
        ),
    )


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not current_user():
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)

    return wrapped


@app.after_request
def after_request(response):
    request_line = f"{request.method} {request_target()} {request.environ.get('SERVER_PROTOCOL', 'HTTP/1.1')}"
    access_line = (
        f'{client_ip()} - - [{combined_log_time()}] "{log_escape(request_line)}" '
        f'{response.status_code} {response_size(response)} '
        f'"{log_escape(request.headers.get("Referer"))}" '
        f'"{log_escape(request.headers.get("User-Agent"))}"'
    )
    print(access_line, flush=True)
    append_log_line(ACCESS_LOG_PATH, access_line)
    return response


@app.context_processor
def inject_template_context():
    return {"group_name": GROUP_NAME, "current_user": current_user()}


@app.route("/")
def index():
    if current_user():
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        user = get_db().execute(
            "SELECT * FROM users WHERE username = ? AND password = ?",
            (username, password),
        ).fetchone()
        if user:
            session.clear()
            session["user_id"] = user["id"]
            get_db().execute("UPDATE users SET last_login = ? WHERE id = ?", (utc_now(), user["id"]))
            get_db().commit()
            write_audit_event("auth.login.success", f"User {username} signed in", user=user)
            return redirect(request.args.get("next") or url_for("dashboard"))
        error = "Invalid username or password"
        write_audit_event("auth.login.failed", f"Failed login for username={username}")
    return render_template("login.html", error=error)


@app.route("/logout", methods=["POST"])
@login_required
def logout():
    user = current_user()
    write_audit_event("auth.logout", f"User {user['username']} signed out", user=user)
    session.clear()
    return redirect(url_for("login"))


@app.route("/dashboard")
@login_required
def dashboard():
    db = get_db()
    counts = {
        "open": db.execute("SELECT COUNT(*) FROM tickets WHERE status != 'Closed'").fetchone()[0],
        "high": db.execute("SELECT COUNT(*) FROM tickets WHERE priority = 'High'").fetchone()[0],
        "customers": db.execute("SELECT COUNT(*) FROM customers").fetchone()[0],
        "invoices": db.execute("SELECT COUNT(*) FROM invoices WHERE status != 'Paid'").fetchone()[0],
    }
    recent_tickets = db.execute(
        """
        SELECT tickets.*, customers.name AS customer_name, users.full_name AS assignee_name
        FROM tickets
        LEFT JOIN customers ON customers.id = tickets.customer_id
        LEFT JOIN users ON users.id = tickets.assigned_to
        ORDER BY tickets.updated_at DESC
        LIMIT 6
        """
    ).fetchall()
    audit_logs = db.execute("SELECT * FROM audit_logs ORDER BY id DESC LIMIT 8").fetchall()
    return render_template("dashboard.html", counts=counts, recent_tickets=recent_tickets, audit_logs=audit_logs)


@app.route("/tickets", methods=["GET"])
@login_required
def tickets():
    rows = get_db().execute(
        """
        SELECT tickets.*, customers.name AS customer_name, users.full_name AS assignee_name
        FROM tickets
        LEFT JOIN customers ON customers.id = tickets.customer_id
        LEFT JOIN users ON users.id = tickets.assigned_to
        ORDER BY
            CASE tickets.priority WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
            tickets.updated_at DESC
        """
    ).fetchall()
    customers = get_db().execute("SELECT * FROM customers ORDER BY name").fetchall()
    return render_template("tickets.html", tickets=rows, customers=customers)


@app.route("/tickets", methods=["POST"])
@login_required
def create_ticket():
    title = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()
    customer_id = request.form.get("customer_id") or None
    priority = request.form.get("priority", "Medium")
    if not title or not description:
        abort(400, "title and description are required")

    now = utc_now()
    user = current_user()
    cursor = get_db().execute(
        """
        INSERT INTO tickets (customer_id, assigned_to, title, description, status, priority, created_at, updated_at)
        VALUES (?, ?, ?, ?, 'Open', ?, ?, ?)
        """,
        (customer_id, user["id"], title, description, priority, now, now),
    )
    get_db().commit()
    ticket_id = cursor.lastrowid
    write_audit_event("ticket.create", f"Created ticket #{ticket_id}: {title}")
    return redirect(url_for("ticket_detail", ticket_id=ticket_id))


@app.route("/tickets/<int:ticket_id>")
@login_required
def ticket_detail(ticket_id):
    ticket = get_db().execute(
        """
        SELECT tickets.*, customers.name AS customer_name, customers.email AS customer_email,
               customers.company AS customer_company, customers.tier AS customer_tier,
               users.full_name AS assignee_name, users.email AS assignee_email
        FROM tickets
        LEFT JOIN customers ON customers.id = tickets.customer_id
        LEFT JOIN users ON users.id = tickets.assigned_to
        WHERE tickets.id = ?
        """,
        (ticket_id,),
    ).fetchone()
    if not ticket:
        abort(404)
    invoices = get_db().execute(
        "SELECT * FROM invoices WHERE customer_id = ? ORDER BY issued_at DESC",
        (ticket["customer_id"],),
    ).fetchall()
    write_audit_event("ticket.view", f"Viewed ticket #{ticket_id}")
    return render_template("ticket_detail.html", ticket=ticket, invoices=invoices)


@app.route("/search")
@login_required
def search():
    q = request.args.get("q", "")
    results = []
    error = None
    unsafe_sql = None
    if q:
        # VULNERABLE BY DESIGN: this string concatenation is intentionally unsafe.
        # It exists for workshop SQL injection detection and response practice.
        unsafe_sql = (
            "SELECT tickets.id, tickets.title, tickets.status, tickets.priority, customers.name AS customer_name "
            "FROM tickets LEFT JOIN customers ON tickets.customer_id = customers.id "
            "WHERE tickets.title LIKE '%"
            + q
            + "%' OR tickets.description LIKE '%"
            + q
            + "%' OR customers.name LIKE '%"
            + q
            + "%' ORDER BY tickets.updated_at DESC"
        )
        try:
            results = get_db().execute(unsafe_sql).fetchall()
            write_audit_event("ticket.search", f"Search query: {q}")
        except sqlite3.Error as exc:
            error = str(exc)
            write_audit_event("ticket.search.error", f"Search query failed: {q} ({exc})")
    return render_template("search.html", q=q, results=results, error=error, unsafe_sql=unsafe_sql)


@app.route("/profile")
@login_required
def profile():
    user = current_user()
    user_logs = get_db().execute(
        "SELECT * FROM audit_logs WHERE username = ? ORDER BY id DESC LIMIT 10",
        (user["username"],),
    ).fetchall()
    return render_template("profile.html", user=user, user_logs=user_logs)


@app.route("/tools")
@login_required
def tools():
    return render_template("tools.html", command_output=None, command_error=None, encoded_input="")


@app.route("/tools/base64", methods=["POST"])
@login_required
def base64_tool():
    raw_text = request.form.get("text", "")
    # VULNERABLE BY DESIGN: user input is concatenated into a shell command.
    # This intentionally demonstrates command injection through shell=True.
    command = f"echo {raw_text} | base64"
    try:
        completed = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=3,
        )
        write_audit_event("tool.base64", f"Ran Base64 Encoder command: {command}")
        return render_template(
            "tools.html",
            command_output=completed.stdout,
            command_error=completed.stderr,
            encoded_input=raw_text,
            command=command,
        )
    except subprocess.TimeoutExpired:
        write_audit_event("tool.base64.timeout", f"Command timed out: {command}")
        return render_template(
            "tools.html",
            command_output="",
            command_error="Command timed out",
            encoded_input=raw_text,
            command=command,
        ), 500


@app.route("/download")
@login_required
def download():
    requested_file = request.args.get("file", "welcome.txt")
    # VULNERABLE BY DESIGN: no path normalization or directory allow-list check.
    # This intentionally demonstrates path traversal in a controlled lab.
    target_path = DOWNLOAD_DIR / requested_file
    write_audit_event("file.download", f"Downloaded file parameter: {requested_file}")
    with open(target_path, "rb") as handle:
        data = handle.read()
    return Response(
        data,
        mimetype="text/plain",
        headers={"Content-Disposition": f'inline; filename="{Path(requested_file).name}"'},
    )


@app.route("/api/tickets")
@login_required
def api_tickets():
    rows = get_db().execute(
        """
        SELECT tickets.id, tickets.title, tickets.status, tickets.priority,
               customers.name AS customer_name, tickets.updated_at
        FROM tickets
        LEFT JOIN customers ON customers.id = tickets.customer_id
        ORDER BY tickets.updated_at DESC
        LIMIT 10
        """
    ).fetchall()
    return jsonify([dict(row) for row in rows])


@app.route("/api/users/me")
@login_required
def api_users_me():
    user = current_user()
    return jsonify(
        {
            "id": user["id"],
            "username": user["username"],
            "full_name": user["full_name"],
            "email": user["email"],
            "role": user["role"],
            "department": user["department"],
            "group": GROUP_NAME,
        }
    )


@app.route("/api/feedback", methods=["POST"])
@login_required
def api_feedback():
    payload = request.get_json(silent=True) or request.form
    rating = str(payload.get("rating", "neutral"))
    comment = str(payload.get("comment", ""))
    write_audit_event("feedback.submit", f"rating={rating}; comment={comment[:120]}")
    return jsonify({"ok": True, "message": "Feedback received"})


@app.route("/api/notifications")
@login_required
def api_notifications():
    notifications = [
        {"level": "info", "message": "Two tickets need customer follow-up today."},
        {"level": "warning", "message": "One invoice is overdue for a Gold tier customer."},
        {"level": "info", "message": f"{GROUP_NAME} heartbeat received."},
    ]
    return jsonify(notifications)


@app.route("/api/stats")
@login_required
def api_stats():
    db = get_db()
    stats = {
        "open_tickets": db.execute("SELECT COUNT(*) FROM tickets WHERE status = 'Open'").fetchone()[0],
        "in_progress": db.execute("SELECT COUNT(*) FROM tickets WHERE status = 'In Progress'").fetchone()[0],
        "pending_invoices": db.execute("SELECT COUNT(*) FROM invoices WHERE status != 'Paid'").fetchone()[0],
        "recent_audit_events": db.execute("SELECT COUNT(*) FROM audit_logs WHERE id > (SELECT MAX(id) - 20 FROM audit_logs)").fetchone()[0],
    }
    return jsonify(stats)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "group": GROUP_NAME, "timestamp": utc_now()})


@app.errorhandler(404)
def not_found(error):
    return render_template("error.html", title="Not found", message="The requested page was not found."), 404


@app.errorhandler(500)
def server_error(error):
    return render_template("error.html", title="Server error", message=str(error)), 500


init_log_files()
init_db()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

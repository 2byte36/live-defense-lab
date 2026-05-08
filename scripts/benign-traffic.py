#!/usr/bin/env python3
import http.cookiejar
import os
import random
import time
import urllib.error
import urllib.parse
import urllib.request


TARGET_BASE_URL = os.environ.get("TARGET_BASE_URL", "http://helpdesk:5000").rstrip("/")
MIN_DELAY = float(os.environ.get("BENIGN_MIN_DELAY", "4"))
MAX_DELAY = float(os.environ.get("BENIGN_MAX_DELAY", "12"))
USERNAME = os.environ.get("BENIGN_USERNAME", "alice")
PASSWORD = os.environ.get("BENIGN_PASSWORD", "password123")
REQUEST_TIMEOUT = float(os.environ.get("BENIGN_TIMEOUT", "5"))

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 Version/17.4 Safari/605.1.15",
    "Mozilla/5.0 (X11; Linux x86_64) Gecko/20100101 Firefox/125.0",
    "curl/8.0",
    "HelpdeskHealthCheck/1.0",
]

PATHS = [
    "/dashboard",
    "/api/tickets",
    "/health",
    "/profile",
    "/api/stats",
]


class BenignClient:
    def __init__(self):
        self.cookie_jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookie_jar))

    def request(self, path, data=None):
        headers = {
            "Accept": "text/html,application/json;q=0.9,*/*;q=0.8",
            "User-Agent": random.choice(USER_AGENTS),
        }
        encoded_data = None
        if data is not None:
            encoded_data = urllib.parse.urlencode(data).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"

        request = urllib.request.Request(
            f"{TARGET_BASE_URL}{path}",
            data=encoded_data,
            headers=headers,
            method="POST" if encoded_data else "GET",
        )
        with self.opener.open(request, timeout=REQUEST_TIMEOUT) as response:
            response.read(2048)
            return response.status

    def login(self):
        return self.request("/login", {"username": USERNAME, "password": PASSWORD})


def sleep_random_interval():
    if MAX_DELAY < MIN_DELAY:
        delay = MIN_DELAY
    else:
        delay = random.uniform(MIN_DELAY, MAX_DELAY)
    time.sleep(delay)


def main():
    client = BenignClient()
    logged_in = False
    print(f"benign traffic generator targeting {TARGET_BASE_URL}", flush=True)

    while True:
        try:
            path = random.choice(PATHS)
            if path != "/health" and not logged_in:
                client.login()
                logged_in = True

            status = client.request(path)
            if status in (401, 403):
                logged_in = False
            print(f"benign request path={path} status={status}", flush=True)
        except urllib.error.HTTPError as exc:
            if exc.code in (401, 403):
                logged_in = False
            print(f"benign request http_error={exc.code}", flush=True)
        except Exception as exc:
            logged_in = False
            print(f"benign request error={type(exc).__name__}: {exc}", flush=True)

        sleep_random_interval()


if __name__ == "__main__":
    main()

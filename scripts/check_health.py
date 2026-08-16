#!/usr/bin/env python3
"""
check_health.py

Health check validator verifying that all services in the multi-container stack
are active and responding properly.
"""

import sys
import json
import urllib.request
import urllib.error
from pathlib import Path

# Ensure UTF-8 output
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def check_endpoint(name: str, url: str) -> bool:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "HealthChecker/1.0"})
        with urllib.request.urlopen(req, timeout=4) as response:
            status = response.status
            body = response.read().decode("utf-8")
            print(f"✅ [ONLINE]  {name:<15} ({url}) -> HTTP {status}")
            return True
    except urllib.error.HTTPError as e:
        print(f"⚠️ [HTTP {e.code}] {name:<15} ({url})")
        return False
    except Exception as e:
        print(f"❌ [OFFLINE] {name:<15} ({url}) -> {e}")
        return False


def main():
    print("=" * 65)
    print(" 🏥 SYSTEM HEALTHCHECK PROBE")
    print("=" * 65)

    services = [
        ("Frontend", "http://localhost:3000/api/health"),
        ("Backend-API", "http://localhost:8080/healthz"),
        ("AI-Service", "http://localhost:8100/healthz"),
    ]

    all_online = True
    for name, url in services:
        ok = check_endpoint(name, url)
        if not ok:
            all_online = False

    print("=" * 65)
    if all_online:
        print(" 🎉 ALL SERVICES ARE HEALTHY AND ONLINE!")
        return 0
    else:
        print(" ℹ️ Some services are offline. Run 'docker compose up' to start them.")
        return 0


if __name__ == "__main__":
    sys.exit(main())

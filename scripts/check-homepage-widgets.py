#!/usr/bin/env python3
"""Verify homepage widget URLs match the live Service ports.

Homepage proxies widgets server-side. If `url:` omits a port it silently
falls back to :80, which nothing listens on -> ETIMEDOUT on every poll, and
the only symptom is a red tile. This cross-checks values.yaml against the
cluster so the mistake can't be committed.

Usage: python3 scripts/check-homepage-widgets.py
Exits 1 on any mismatch.
"""

import re
import subprocess
import sys
from pathlib import Path

VALUES = Path(__file__).parent.parent / "k3s-ha-cluster/homepage/values.yaml"

# url: http://<svc>.<ns>.svc.cluster.local[:<port>]
URL_RE = re.compile(r"url:\s*http://([\w.-]+)\.svc\.cluster\.local(?::(\d+))?")

failures = []


def service_port(svc: str, ns: str) -> str | None:
    """First port the Service exposes, or None if the Service is gone."""
    out = subprocess.run(
        ["kubectl", "get", "svc", svc, "-n", ns, "-o", "jsonpath={.spec.ports[0].port}"],
        capture_output=True,
        text=True,
    )
    return out.stdout.strip() or None


for svc_ns, port in URL_RE.findall(VALUES.read_text()):
    svc, _, ns = svc_ns.rpartition(".")
    live = service_port(svc, ns)
    if live is None:
        failures.append(f"{svc}.{ns}: no such Service")
    elif (port or "80") != live:
        given = port or "none (defaults to 80)"
        failures.append(f"{svc}.{ns}: url port {given}, Service listens on {live}")

if failures:
    print("homepage widget URL mismatches:")
    print("\n".join(f"  - {f}" for f in failures))
    sys.exit(1)

print("all homepage widget URLs match their Service ports")
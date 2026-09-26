#!/usr/bin/env python3
"""Read-only instant PromQL query against the Grafana Cloud Metrics API."""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("promql", help="Instant PromQL expression")
    parser.add_argument("--at", help="Optional evaluation time (RFC3339 or Unix seconds)")
    args = parser.parse_args()

    names = (
        "GRAFANA_METRICS_QUERY_URL",
        "GRAFANA_METRICS_INSTANCE_ID",
        "GRAFANA_METRICS_READ_TOKEN",
    )
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        parser.error("Missing environment variables: " + ", ".join(missing))

    endpoint = os.environ[names[0]].rstrip("/")
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.query or parsed.fragment:
        parser.error("GRAFANA_METRICS_QUERY_URL must be an HTTPS query endpoint")

    params = {"query": args.promql}
    if args.at:
        params["time"] = args.at
    url = endpoint + "/api/v1/query?" + urllib.parse.urlencode(params)
    credentials = f"{os.environ[names[1]]}:{os.environ[names[2]]}".encode()
    request = urllib.request.Request(
        url,
        headers={"Authorization": "Basic " + base64.b64encode(credentials).decode()},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        print(f"Grafana query failed (HTTP {exc.code})", file=sys.stderr)
        return 1
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"Grafana query failed ({type(exc).__name__})", file=sys.stderr)
        return 1

    print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0 if payload.get("status") == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())

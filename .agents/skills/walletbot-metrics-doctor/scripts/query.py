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
from pathlib import Path
from time import time


def local_values(path: Path, names: tuple[str, ...]) -> dict[str, str]:
    if not path.is_file():
        return {}
    values = {}
    for line in path.read_text().splitlines():
        key, separator, value = line.partition("=")
        if not separator or key.strip() not in names:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("promql", help="Instant PromQL expression")
    parser.add_argument("--at", help="Optional evaluation time (RFC3339 or Unix seconds)")
    parser.add_argument(
        "--series-days",
        type=int,
        help="Treat the expression as a series selector and list metric names/scopes seen in the last N days",
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path(__file__).resolve().parents[4] / "packages/backend/.env.local",
        help="Local ignored env file (default: packages/backend/.env.local)",
    )
    args = parser.parse_args()
    if args.series_days is not None and args.series_days < 1:
        parser.error("--series-days must be positive")
    if args.series_days is not None and args.at:
        parser.error("--at cannot be used with --series-days")

    names = (
        "GRAFANA_METRICS_QUERY_URL",
        "GRAFANA_METRICS_INSTANCE_ID",
        "GRAFANA_METRICS_READ_TOKEN",
    )
    config = local_values(args.env_file, names)
    config.update({name: os.environ[name] for name in names if os.environ.get(name)})
    missing = [name for name in names if not config.get(name)]
    if missing:
        parser.error("Missing environment variables: " + ", ".join(missing))

    endpoint = config[names[0]].rstrip("/")
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.query or parsed.fragment:
        parser.error("GRAFANA_METRICS_QUERY_URL must be an HTTPS query endpoint")

    if args.series_days is None:
        params = {"query": args.promql}
        if args.at:
            params["time"] = args.at
        url = endpoint + "/api/v1/query?" + urllib.parse.urlencode(params)
    else:
        params = {
            "match[]": args.promql,
            "start": str(int(time() - args.series_days * 86400)),
        }
        url = endpoint + "/api/v1/series?" + urllib.parse.urlencode(params)
    credentials = f"{config[names[1]]}:{config[names[2]]}".encode()
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

    if payload.get("status") != "success":
        print("Grafana query returned an error", file=sys.stderr)
        return 1
    if args.series_days is not None:
        series = sorted(
            {
                (item.get("__name__", ""), item.get("deployment_environment", ""))
                for item in payload.get("data", [])
            }
        )
        print(json.dumps([{"name": name, "scope": scope} for name, scope in series], indent=2))
    else:
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

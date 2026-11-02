#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_ID=live.walletbot.app
EMAIL="sofia.demo$(date +%Y%m%d%H%M%S)@walletbot.test"
PASSWORD="${DEMO_PASSWORD:-demo-video-2026}"
DAY="$(TZ=America/Argentina/Buenos_Aires date +%F)"

(cd "$REPO_ROOT/packages/backend" && npx convex run usability/actions:provisionDemoUser \
    "{\"email\":\"$EMAIL\",\"name\":\"Sofía Martínez\",\"password\":\"$PASSWORD\",\"sessionDay\":\"$DAY\"}")

adb shell pm clear "$APP_ID" >/dev/null
adb shell cmd locale set-app-locales "$APP_ID" --locales es-AR
adb shell pm grant "$APP_ID" android.permission.RECORD_AUDIO

maestro test -e EMAIL="$EMAIL" -e PASSWORD="$PASSWORD" setup.yaml
echo "Ready: signed in as $EMAIL"

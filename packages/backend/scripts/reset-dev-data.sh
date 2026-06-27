#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT="dev"
YES="false"
ALLOW_PROD="false"

usage() {
  cat <<'EOF'
Usage:
  pnpm reset:dev-data --yes
  pnpm reset:dev-data --deployment local --yes

Clears WalletBot user data from a Convex deployment by importing an empty
snapshot for the synced tables. This is intended for dev/QA after breaking
schema changes such as making account/category/tag appearance fields required.

Options:
  --deployment <ref>  Convex deployment ref/name. Defaults to "dev".
  --yes              Skip confirmation prompt.
  --allow-prod       Allow --deployment prod. Not recommended.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --)
      shift
      ;;
    --deployment)
      DEPLOYMENT="${2:?Missing value for --deployment}"
      shift 2
      ;;
    --yes|-y)
      YES="true"
      shift
      ;;
    --allow-prod)
      ALLOW_PROD="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$DEPLOYMENT" == "prod" && "$ALLOW_PROD" != "true" ]]; then
  echo "Refusing to reset prod without --allow-prod." >&2
  exit 2
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "Missing required command: zip" >&2
  exit 1
fi

TABLES=(
  accounts
  categories
  tags
  transactions
  transactionTags
  tombstones
  syncCounters
)

if [[ "$YES" != "true" ]]; then
  echo "This will delete all documents in these Convex tables on '$DEPLOYMENT':"
  printf '  - %s\n' "${TABLES[@]}"
  echo
  read -r -p "Type RESET to continue: " CONFIRMATION
  if [[ "$CONFIRMATION" != "RESET" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for table in "${TABLES[@]}"; do
  mkdir -p "$TMPDIR/$table"
  : > "$TMPDIR/$table/documents.jsonl"
done

SNAPSHOT="$TMPDIR/walletbot-empty-user-data.zip"
(
  cd "$TMPDIR"
  zip -qr "$SNAPSHOT" "${TABLES[@]}"
)

echo "Importing empty snapshot into Convex deployment '$DEPLOYMENT'..."
pnpm convex import "$SNAPSHOT" --replace --deployment "$DEPLOYMENT" --yes
echo "Done. You can now run: pnpm convex dev"

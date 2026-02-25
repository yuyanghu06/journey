#!/bin/sh
set -e

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set" >&2
  exit 1
fi

echo "[prisma] Starting schema push to database..."
DATABASE_URL="$DATABASE_URL" DEBUG="prisma:schema-engine,prisma:info,prisma:warn,prisma:error" npx prisma db push --accept-data-loss
echo "[prisma] Schema push complete."

exec node dist/main

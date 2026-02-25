#!/bin/sh
set -e

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set" >&2
  exit 1
fi

echo "[prisma] Applying migrations..."
# In production, use migrations (deterministic, auditable) instead of `db push`.
# This will create new tables/columns based on committed migration files in `prisma/migrations`.
npx prisma migrate deploy
echo "[prisma] Migrations applied."

exec node dist/main

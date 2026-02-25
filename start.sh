#!/bin/sh
set -e

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set" >&2
  exit 1
fi

DATABASE_URL="$DATABASE_URL" npx prisma db push --accept-data-loss

exec node dist/main

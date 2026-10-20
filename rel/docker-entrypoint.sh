#!/bin/sh
# Prepares /data on first start, then runs the Atlas release.
#
#   /data/atlas.db           SQLite database (migrated automatically at boot)
#   /data/skills/            editable copy of the Markdown skills
#   /data/uploads/           experiment result files
#   /data/.secret_key_base   generated once, reused across restarts
set -eu

DATA_DIR="${ATLAS_DATA_DIR:-/data}"
mkdir -p "$DATA_DIR/uploads"

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  if [ ! -s "$DATA_DIR/.secret_key_base" ]; then
    head -c 64 /dev/urandom | base64 | tr -d '\n' > "$DATA_DIR/.secret_key_base"
    chmod 600 "$DATA_DIR/.secret_key_base"
  fi
  SECRET_KEY_BASE="$(cat "$DATA_DIR/.secret_key_base")"
  export SECRET_KEY_BASE
fi

# Seed the editable skills from the release the first time only, so your
# edits survive image upgrades. Delete /data/skills to reset to the defaults.
if [ ! -d "$DATA_DIR/skills" ]; then
  cp -R /app/lib/atlas-*/priv/skills "$DATA_DIR/skills"
fi

export DATABASE_PATH="${DATABASE_PATH:-$DATA_DIR/atlas.db}"
export ATLAS_SKILLS_DIR="${ATLAS_SKILLS_DIR:-$DATA_DIR/skills}"
export ATLAS_UPLOADS_DIR="${ATLAS_UPLOADS_DIR:-$DATA_DIR/uploads}"
export PHX_SERVER=true

exec "$@"

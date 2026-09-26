#!/usr/bin/env sh
set -eu

target=${1:-apk}
if [ "$target" != "apk" ] && [ "$target" != "appbundle" ]; then
  echo "Usage: $0 [apk|appbundle] [additional flutter arguments...]" >&2
  exit 2
fi
shift || true

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_path="$repo_root/config/buildx.public.json"

if [ ! -f "$config_path" ]; then
  echo "CRITICAL: Config file '$config_path' does not exist! Release builds require valid Supabase configuration." >&2
  exit 1
fi

if ! grep -q '"SUPABASE_URL"[[:space:]]*:[[:space:]]*"https://' "$config_path"; then
  echo "CRITICAL: Missing or invalid SUPABASE_URL in '$config_path'!" >&2
  exit 1
fi

if ! grep -q '"SUPABASE_PUBLISHABLE_KEY"[[:space:]]*:[[:space:]]*"sb_' "$config_path" && \
   ! grep -q '"SUPABASE_ANON_KEY"[[:space:]]*:[[:space:]]*"ey' "$config_path"; then
  echo "CRITICAL: Missing SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY in '$config_path'!" >&2
  exit 1
fi

echo "==> Verified build configuration from $config_path"

exec flutter build "$target" --release \
  "--dart-define-from-file=$config_path" \
  "$@"

#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec flutter run \
  "--dart-define-from-file=$repo_root/config/buildx.public.json" \
  "$@"

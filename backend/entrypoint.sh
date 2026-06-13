#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
BLOB_DIR="${BLOB_DIR:-$DATA_DIR/blobs}"

mkdir -p "$BLOB_DIR"
chown -R app:app "$DATA_DIR"

exec su-exec app "$@"

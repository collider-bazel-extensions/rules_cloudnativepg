#!/usr/bin/env bash
# Generic install-wrapper. Takes the install-bin's filename (without .sh)
# as the single arg via the sh_binary's `args` attr; resolves it via
# runfiles. Avoids duplicating one wrapper per operator version.
set -euo pipefail

INSTALL_BIN_NAME="${1:?usage: $0 <install_bin_name>}"
CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
INSTALL_BIN="${RUNFILES_DIR}/_main/tests/${INSTALL_BIN_NAME}.sh"
[[ -x "$INSTALL_BIN" ]] || { echo "wrapper: $INSTALL_BIN_NAME not at $INSTALL_BIN" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

exec "$INSTALL_BIN"

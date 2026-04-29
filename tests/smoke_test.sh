#!/usr/bin/env bash
# Default smoke: write a row on the primary postgres pod, read it back
# from a standby. Proves CNPG's operator + streaming replication both
# work — not just "postgres pod is up".
#
# Strategy:
#   1. Apply the 3-instance Cluster CR.
#   2. Wait for `.status.phase == "Cluster in healthy state"` (CNPG's
#      ready signal). The phase string is documented in CNPG's CRD ref.
#   3. Discover primary + standby pods via the `cnpg.io/instanceRole`
#      label CNPG sets on each pod.
#   4. `kubectl exec` into the primary, CREATE TABLE + INSERT a unique
#      payload.
#   5. Poll a standby for the row (replication is async; up to 30s).
#   6. Assert the standby's SELECT returns the payload.
set -euo pipefail

CLUSTER_YAML="${1:?usage: $0 <cluster.yaml>}"
[[ -f "$CLUSTER_YAML" ]] || { echo "missing cluster yaml: $CLUSTER_YAML" >&2; exit 1; }

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")
NS="smoke"
CLUSTER="smoke"
PAYLOAD="rules_cnpg-smoke-$RANDOM-$RANDOM"

echo "smoke_test: applying Cluster CR (3 instances)"
"${KCTL[@]}" apply -f "$CLUSTER_YAML"

echo "smoke_test: waiting for Cluster '$CLUSTER' to reach phase 'Cluster in healthy state' (~3-5min — pulls postgres image)"
deadline=$(( $(date +%s) + 600 ))
while (( $(date +%s) < deadline )); do
  phase=$("${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
  ready_inst=$("${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" \
      -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)
  echo "smoke_test:   phase='$phase' readyInstances='$ready_inst'"
  if [[ "$phase" == "Cluster in healthy state" && "$ready_inst" == "3" ]]; then
    break
  fi
  sleep 5
done
if [[ "$phase" != "Cluster in healthy state" || "$ready_inst" != "3" ]]; then
  echo "smoke_test: FAIL — cluster never reached healthy with 3 ready instances" >&2
  echo "---- last status ----" >&2
  "${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" -o yaml >&2 || true
  echo "---- pods ----" >&2
  "${KCTL[@]}" -n "$NS" get pods -l "cnpg.io/cluster=$CLUSTER" >&2 || true
  exit 1
fi
echo "smoke_test: OK — cluster healthy"

echo "smoke_test: discovering primary + standby pods"
PRIMARY=$("${KCTL[@]}" -n "$NS" get pod \
    -l "cnpg.io/cluster=$CLUSTER,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}')
STANDBY=$("${KCTL[@]}" -n "$NS" get pod \
    -l "cnpg.io/cluster=$CLUSTER,cnpg.io/instanceRole=replica" \
    -o jsonpath='{.items[0].metadata.name}')
[[ -n "$PRIMARY" ]] || { echo "smoke_test: FAIL — no primary pod found" >&2; exit 1; }
[[ -n "$STANDBY" ]] || { echo "smoke_test: FAIL — no standby pod found" >&2; exit 1; }
echo "smoke_test:   primary=$PRIMARY  standby=$STANDBY"

# CNPG configures pg_hba so the in-pod `postgres` UNIX user can connect
# without a password via local trust on the unix socket. The `postgres`
# container is the one running the postgres process.
PSQL=(--container=postgres -- psql -U postgres -d postgres -tA -c)

echo "smoke_test: writing on primary (payload=$PAYLOAD)"
"${KCTL[@]}" -n "$NS" exec "$PRIMARY" "${PSQL[@]}" \
    "CREATE TABLE IF NOT EXISTS smoke (val TEXT); INSERT INTO smoke VALUES ('$PAYLOAD');" \
    >/dev/null

echo "smoke_test: polling standby for the payload (replication is async)"
deadline=$(( $(date +%s) + 30 ))
while (( $(date +%s) < deadline )); do
  got=$("${KCTL[@]}" -n "$NS" exec "$STANDBY" "${PSQL[@]}" \
      "SELECT val FROM smoke WHERE val = '$PAYLOAD';" 2>/dev/null || true)
  if [[ "$got" == "$PAYLOAD" ]]; then
    echo "smoke_test: OK — standby returned payload (replication works)"
    exit 0
  fi
  sleep 1
done

echo "smoke_test: FAIL — standby never saw the payload (replication broken?)" >&2
echo "  got: '$got'  expected: '$PAYLOAD'" >&2
"${KCTL[@]}" -n "$NS" exec "$PRIMARY" "${PSQL[@]}" "SELECT * FROM smoke;" >&2 || true
"${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" -o yaml >&2 || true
exit 1

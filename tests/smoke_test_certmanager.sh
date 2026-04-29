#!/usr/bin/env bash
# Cert-manager-TLS smoke. Proves the rules_certmanager + rules_cloudnativepg
# composition: a Cluster CR that consumes a cert-manager-issued Secret
# for its postgres server cert. If the certs are wrong (missing keys,
# bad SANs, etc.), CNPG won't reach healthy.
#
# Strategy:
#   1. Apply the bundle (ClusterIssuer + Certificate + Cluster CR).
#   2. Wait for the cert-manager Secret `smoke-server-tls` to materialize.
#      (Proves cert-manager actually issued a cert.)
#   3. Wait for the CNPG Cluster to reach healthy state.
#      (Proves CNPG accepted the cert-manager-issued Secret as its
#      server TLS material.)
#   4. Verify the Secret carries cert-manager's annotations — proves
#      the Secret was issued by cert-manager (not minted by CNPG itself
#      from its own internal CA).
set -euo pipefail

CLUSTER_YAML="${1:?usage: $0 <cluster_with_certmanager.yaml>}"
[[ -f "$CLUSTER_YAML" ]] || { echo "missing cluster yaml: $CLUSTER_YAML" >&2; exit 1; }

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")
NS="smoke"
CLUSTER="smoke"
SECRET="smoke-server-tls"

echo "smoke_test: applying ClusterIssuer + Certificate + Cluster CR"
"${KCTL[@]}" apply -f "$CLUSTER_YAML"

echo "smoke_test: waiting for cert-manager-issued Secret '$SECRET'"
deadline=$(( $(date +%s) + 60 ))
while (( $(date +%s) < deadline )); do
  if "${KCTL[@]}" -n "$NS" get secret "$SECRET" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
"${KCTL[@]}" -n "$NS" get secret "$SECRET" >/dev/null \
  || { echo "smoke_test: FAIL — Secret '$SECRET' never materialized" >&2; exit 1; }
echo "smoke_test: OK — cert-manager issued the Secret"

# Verify cert-manager actually owns the Secret. cert-manager stamps each
# Secret it issues with these annotations.
echo "smoke_test: verifying Secret carries cert-manager annotations"
issuer_name=$("${KCTL[@]}" -n "$NS" get secret "$SECRET" \
    -o jsonpath='{.metadata.annotations.cert-manager\.io/issuer-name}')
if [[ -z "$issuer_name" ]]; then
  echo "smoke_test: FAIL — Secret missing cert-manager.io/issuer-name annotation (cert-manager didn't issue it?)" >&2
  "${KCTL[@]}" -n "$NS" get secret "$SECRET" -o yaml >&2
  exit 1
fi
echo "smoke_test: OK — Secret issued by cert-manager (issuer=$issuer_name)"

echo "smoke_test: waiting for Cluster '$CLUSTER' healthy (image pull + cert validation)"
deadline=$(( $(date +%s) + 600 ))
while (( $(date +%s) < deadline )); do
  phase=$("${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
  ready_inst=$("${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" \
      -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)
  echo "smoke_test:   phase='$phase' readyInstances='$ready_inst'"
  if [[ "$phase" == "Cluster in healthy state" && "$ready_inst" == "1" ]]; then
    break
  fi
  sleep 5
done
if [[ "$phase" != "Cluster in healthy state" || "$ready_inst" != "1" ]]; then
  echo "smoke_test: FAIL — cluster never reached healthy with the cert-manager Secret" >&2
  "${KCTL[@]}" -n "$NS" get cluster "$CLUSTER" -o yaml >&2 || true
  "${KCTL[@]}" -n "$NS" get pods -l "cnpg.io/cluster=$CLUSTER" >&2 || true
  "${KCTL[@]}" -n "$NS" describe pod -l "cnpg.io/cluster=$CLUSTER" >&2 || true
  exit 1
fi
echo "smoke_test: OK — CNPG accepted the cert-manager-issued cert and the cluster is healthy"

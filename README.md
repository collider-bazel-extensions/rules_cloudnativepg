# rules_cloudnativepg

Hermetic [CloudNativePG](https://cloudnative-pg.io/) operator install
for Bazel test compositions. The CNPG operator manages declarative
PostgreSQL clusters via the `Cluster` CR — primary + streaming
replicas, automatic failover, point-in-time recovery, etc.

```python
load("@rules_cloudnativepg//:defs.bzl",
     "cloudnativepg_install", "cloudnativepg_health_check")

cloudnativepg_install(name = "cnpg_install_bin")
cloudnativepg_health_check(name = "cnpg_health_bin")
```

That installs the **operator**. Postgres clusters themselves are
consumer-authored `Cluster` CRs — see [Defining Clusters](#defining-clusters)
and [`examples/`](examples/) for ready-to-copy YAML.

**Pinned operator versions:** `0.27.1` (CNPG 1.28.1) and `0.28.0`
(CNPG 1.29.0). Default = 0.28.0; pick via `operator_version = "..."`.
Both versions are CI-matrix-tested.

**Supported platforms (v0.1):** any platform where rules_kubectl runs.
Validated on Linux x86\_64 in CI; macOS pending.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Defining Clusters](#defining-clusters)
- [Macros](#macros)
- [Composition with rules_certmanager](#composition-with-rules_certmanager)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Comparison with rules_pg](#comparison-with-rules_pg)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_cloudnativepg", version = "0.1.0")
```

`rules_cloudnativepg` is **Bzlmod-only** in v0.1. Until BCR, consume
via `archive_override` or a git pin. Transitively pulls in
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl).

---

## Quickstart

```python
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_cloudnativepg//:defs.bzl",
     "cloudnativepg_install", "cloudnativepg_health_check")
load("@rules_kubectl//:defs.bzl", "kubectl_apply")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# 1. Cluster.
kind_cluster(name = "cluster", k8s_version = "1.35")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. CNPG operator.
cloudnativepg_install(name = "cnpg_install_bin")        # default operator 0.28.0
cloudnativepg_health_check(name = "cnpg_health_bin")
sh_binary(name = "cnpg_install_wrapper", srcs = ["install_wrapper.sh"], data = [":cnpg_install_bin"])
sh_binary(name = "cnpg_health_wrapper",  srcs = ["health_wrapper.sh"],  data = [":cnpg_health_bin"])

itest_service(
    name = "cnpg_svc",
    exe = ":cnpg_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":cnpg_health_wrapper",
)

# 3. The actual postgres cluster — your YAML, applied with kubectl_apply.
kubectl_apply(
    name = "app_db_install_bin",
    manifests = ["my_cluster.yaml"],   # see "Defining Clusters" below
    wait_for_rollouts = ["sts/app-db"],
    wait_timeout = "600s",
)
sh_binary(name = "app_db_install_wrapper", srcs = ["install_wrapper.sh"], data = [":app_db_install_bin"])

itest_service(
    name = "app_db_svc",
    exe = ":app_db_install_wrapper",
    deps = [":cnpg_svc"],   # waits for operator + CRDs before applying Cluster CR
    health_check = ":...",
)
```

The `install_wrapper.sh` / `health_wrapper.sh` shape matches every
sibling rule set — see `tests/install_wrapper.sh` for the canonical
~20-line file (sources kind's env file under `set -a`, exec's the bin).

---

## Defining Clusters

`rules_cloudnativepg` deliberately does NOT ship a `cloudnativepg_cluster`
Bazel rule in v0.1. Cluster CRs have 30+ tunables; a v0.1 macro would
either flatten them all (becomes a YAML translator) or hide most.
Instead: **author your `Cluster` CR as YAML** and apply it via
`kubectl_apply`.

The smallest viable Cluster (1 instance, no HA — same shape as
[`rules_pg`](https://github.com/collider-bazel-extensions/rules_pg)):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
  namespace: app
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  storage:
    size: 1Gi
    storageClass: standard
```

3-instance HA (CNPG's value-add over `rules_pg`):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
  namespace: app
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  storage:
    size: 10Gi
    storageClass: standard
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
```

See [`examples/`](examples/) for full files. Ready to copy.

---

## Macros

### `cloudnativepg_install`

```python
cloudnativepg_install(
    name = "cnpg_install_bin",
    operator_version = "0.28.0",   # or "0.27.1"; default 0.28.0
    namespace = "cnpg-system",
    wait_timeout = "300s",
)
```

Expands to a `kubectl_apply(...)` target that:

- Applies the pinned per-version operator manifest
  (`@rules_cloudnativepg//private/manifests:cloudnativepg-<ver>.yaml`).
- `create_namespace = True`, `server_side = True`.
- `wait_for_deployments = ["cnpg-cloudnative-pg"]`.
- `wait_for_crds = ["clusters.postgresql.cnpg.io"]` — load-bearing:
  prevents downstream services from racing the operator's CRD installer.

Drops into `itest_service.exe`.

### `cloudnativepg_health_check`

```python
cloudnativepg_health_check(name = "cnpg_health_bin", namespace = "cnpg-system")
```

Drops into `itest_service.health_check`.

---

## Composition with rules_certmanager

CNPG's `Cluster.spec.certificates` block lets you point the operator at
external Secrets for the postgres server cert + CA. The natural fit is
cert-manager-issued certs.

`tests/smoke_test_certmanager.sh` is the canonical example, exercising
`kind → cert_manager → cnpg_install → Cluster (with cert-manager TLS) → assertion`.

The shape consumers copy:

```yaml
# 1. Issuer (use a real CA-backed issuer in production)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: app-selfsigned}
spec: {selfSigned: {}}
---
# 2. Certificate that produces the Secret CNPG consumes
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: app-db-server-cert, namespace: app}
spec:
  secretName: app-db-server-tls
  issuerRef: {name: app-selfsigned, kind: ClusterIssuer}
  commonName: app-db-rw.app.svc
  dnsNames: [app-db-rw.app.svc.cluster.local, ...]   # all per-pod + Service names
---
# 3. Cluster pointing at the Secret
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: app-db, namespace: app}
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  storage: {size: 1Gi, storageClass: standard}
  certificates:
    serverTLSSecret: app-db-server-tls
    serverCASecret: app-db-server-tls
```

`examples/with_cert_manager_tls.yaml` has the full file with all SAN
entries.

**Note:** the chart does NOT expose a cert-manager toggle for the
operator's **webhook** cert — the operator self-signs that internally.
cert-manager + CNPG integration is at the **postgres TLS layer**.

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| Operator manifest | Fully hermetic per supported version. Pre-rendered from chart .tgz, sha-pinned in `tools/versions.bzl`. | Re-render with `bash tools/render_cnpg.sh <ver>`. |
| `kubectl` | Inherited from `rules_kubectl`. | |
| Target cluster | Out of scope. | |
| Postgres container image | Pulled at runtime by the cluster's nodes (`ghcr.io/cloudnative-pg/postgresql:<tag>`). ~250MB. | Future: pre-load via `kind_cluster.images`. |
| Webhook cert | Operator self-signs internally. | Chart doesn't expose a cert-manager toggle for the webhook. |

---

## Comparison with rules_pg

| | `rules_pg` | `rules_cloudnativepg` |
|---|---|---|
| Postgres flavor | Single-node container, plain `postgres:` image | Operator-managed Cluster CR (1 to N instances) |
| HA | No | Yes — primary + streaming replicas |
| Failover | Manual (kill the pod, no replacement) | Automatic (operator promotes a standby) |
| Cluster networking | One Service → one pod | Operator manages `<cluster>-rw` (primary) + `<cluster>-ro` (replicas) Services |
| Backups | None (consumer brings their own) | Built-in (Barman Cloud — deferred from v0.1 of this rule) |
| Smoke runtime | ~30s | ~3-5min (postgres image pull + 3-instance startup) |

Pick `rules_pg` for "I just need a postgres pod for my Bazel test."
Pick `rules_cloudnativepg` for "I'm testing something that depends on
CNPG's operator behavior — failover, replication, the Cluster CR."

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New rules need an analysis test in `tests/analysis_tests.bzl`.
- Bumping pinned operator versions: edit `tools/versions.bzl` + the
  per-version `helm_template + sh_binary` block in `tools/BUILD.bazel`,
  add the version to defs.bzl's `_MANIFEST_BY_VERSION`, add the manifest
  filegroup to `private/manifests/BUILD.bazel`, run
  `bash tools/render_cnpg.sh <new-version>`, commit.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted

- macOS validation (the rule is platform-independent).
- HA failover smoke (kill primary, assert standby promotion).
- Backup smoke (would compose with minio for S3-compatible storage).

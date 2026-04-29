# rules_cloudnativepg — design decisions

Hermetic [CloudNativePG](https://cloudnative-pg.io/) operator install
for Bazel test compositions. Pure glue over
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl)
and (at maintainer time)
[`rules_helm`](https://github.com/collider-bazel-extensions/rules_helm).

Same architecture as `rules_loki` / `rules_grafana` — macros wrapping
`kubectl_apply` / `kubectl_apply_health_check`, no per-rule launcher /
toolchain. **Differs in two ways:**

1. **Multi-version:** ships pre-rendered manifests for two operator
   versions (0.27.x + 0.28.x) and the macros take an `operator_version`.
2. **Multi-smoke:** default smoke (HA replication round-trip) + a
   second smoke that composes with `rules_certmanager` for postgres TLS.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** | Sibling-family |
| 2 | Architecture | **Layered.** Macros wrapping `kubectl_apply` / `kubectl_apply_health_check`. | rules_loki / rules_grafana |
| 3 | Manifest provisioning | Operator helm chart **pre-rendered** per supported version into `private/manifests/cloudnativepg-<ver>.yaml` via `rules_helm`. Committed. | rules_loki pattern |
| 4 | Multi-version | Two operator versions side-by-side: **`0.27.1`** (CNPG 1.28.1) and **`0.28.0`** (CNPG 1.29.0). Default = 0.28.0. Each version has its own pinned chart, its own committed manifest, and its own CI matrix cell. | Pattern from rules_kind's `k8s_version` (which ships 1.29 + 1.32 side-by-side) |
| 5 | Public surface | `cloudnativepg_install` (`operator_version` attr), `cloudnativepg_health_check`. **No `cloudnativepg_cluster` rule.** Cluster CRs are 30+ tunables — a v0.1 macro would either flatten them all (becomes a YAML translator) or hide most. Better to document the YAML pattern (see `examples/`) and add a Bazel-shaped Cluster rule when consumer patterns clarify. | Per-user directive |
| 6 | Namespace | `cnpg-system` (default, idempotent create). Operator is namespace-singleton — installing into a different namespace works but the operator-name convention is `cnpg-system`. | Chart-shaped |
| 7 | Wait shape | Both `wait_for_deployments = ["cnpg-cloudnative-pg"]` AND `wait_for_crds = ["clusters.postgresql.cnpg.io"]`. The CRD wait is **load-bearing** — without it, downstream services that apply `Cluster` CRs immediately after install race the operator's CRD installer. Same race lesson rules_argocd needed. | CNPG-specific |
| 8 | Webhook cert | Chart's default — the operator self-signs and self-injects its own caBundle into the WebhookConfiguration. The chart does **not** expose a cert-manager toggle for the webhook cert; that path lives inside the operator process. | CNPG-specific |
| 9 | cert-manager integration scope | The cert-manager + CNPG composition is at the **postgres server cert** layer (CNPG's `Cluster.spec.certificates`), not the webhook layer. The cert-manager smoke proves the production pattern: cert-manager-issued server cert → CNPG consumes → cluster comes up healthy. | CNPG-specific |
| 10 | rules_kubectl dependency | **Public dep.** Macros expand to its rules in consumer code. | Layered architecture |
| 11 | rules_helm dependency | **Dev-only.** Maintainer-side render only. | rules_loki pattern |
| 12 | rules_certmanager dependency | **Dev-only** for the cert-manager smoke variant. **Not** required for the default install — the operator self-signs. Production deployments wanting cert-manager-managed postgres TLS will add `bazel_dep` on rules_certmanager themselves. | Avoid forcing every consumer to take rules_certmanager |
| 13 | Smoke #1 (default) | **3-instance HA Cluster CR + replication round-trip.** Write a row on the primary pod via `kubectl exec ... psql`, poll a standby for the row, assert it appears. Proves operator + streaming replication + multi-instance HA all work — not just "operator pod is up." Per the family's "exercise the functionality" rule. | rules_pg covers single-node; CNPG's value over rules_pg is HA |
| 14 | Smoke #2 (cert-manager) | rules_certmanager + cert-manager-issued server cert + 1-instance Cluster. Asserts: the cert-manager Secret materializes with the `cert-manager.io/issuer-name` annotation; CNPG accepts the external Secret; cluster reaches healthy state. 1 instance (not 3) is enough — the assertion is "composition works," not HA. | Per-user directive |
| 15 | CI matrix | Default smoke runs against **both** operator versions (0.27.1, 0.28.0). cert-manager smoke runs against the **latest** operator only (no value in re-running the same composition with the older operator). Total: 3 service-test cells. | Pragmatic CI minutes |
| 16 | Naming | snake_case rules/macros, `MixedCaseInfo` providers (none in v0.1), `UPPER_SNAKE` constants. | All siblings |
| 17 | Update workflow | `bash tools/render_cnpg.sh <chart-version>` → thin shim around `bazel run //tools:render_writeback_<dotted_version>`. Rendering each supported version is a separate writeback target. Adding a new version requires edits in 5 places (versions.bzl, BUILD.bazel under tools, MODULE.bazel, defs.bzl, manifests/BUILD.bazel) — see render_cnpg.sh comment. | rules_loki precedent |

## CNPG-specific notes

- **Deployment name** is `<release>-<chart>`, where the chart's `name` is `cloudnative-pg`. We render with release name `cnpg`, so the Deployment is `cnpg-cloudnative-pg`. The `wait_for_deployments` list in defs.bzl matches.
- **The chart bundles CRDs**, but they're applied at install time (not by the operator at runtime). `wait_for_crds` is still load-bearing because server-side apply may briefly hold off the CRD until validation completes; downstream `Cluster` CR applies need to see the CRD.
- **Postgres image major** is consumer-controlled via `Cluster.spec.imageName`. The smoke pins `ghcr.io/cloudnative-pg/postgresql:16.6` for stability + broad operator-version compatibility (both 0.27.1 and 0.28.0 accept it). Production consumers can pin any postgres major CNPG supports.
- **Anonymous-Admin / dangerous defaults**: none. The operator runs with proper RBAC; postgres pods accept connections only via the ClusterIP Services or in-pod unix-socket. Smoke tests use `kubectl exec ... psql -U postgres` (in-pod local trust) rather than network connections — no auth handling required.

## v0.1.0 status (planning)

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only) | planned |
| `cloudnativepg_install` + `cloudnativepg_health_check` macros (operator_version attr) | planned |
| Two pinned operator versions (0.27.1, 0.28.0) rendered + committed | planned |
| `config/cnpg-values.yaml` (exported) | planned |
| Maintainer render flow (per-version) | planned |
| Analysis tests (per-version) | planned |
| In-tree default smoke (kind + operator + 3-instance Cluster + replication round-trip) | planned |
| In-tree cert-manager smoke (kind + cert-manager + operator + cert-manager TLS Cluster) | planned |
| `examples/` (single-instance, HA, cert-manager-TLS) | planned |
| End-to-end `bazel test` runtime | planned (validated under CI Docker; macOS pending) |

## Deferred (not v0.1.0)

- **`cloudnativepg_cluster` Bazel rule** — wrapper around Cluster CR YAML. Add when consumer patterns clarify which tunables belong on the rule's surface vs in the YAML.
- **`Backup` / `ScheduledBackup`** — needs S3-compatible storage (would add minio to the smoke).
- **`Pooler` (PgBouncer)** — its own CR; consumers author YAML.
- **`Publication` / `Subscription` CRs** — logical replication.
- **HA failover smoke** — kill the primary pod, assert a standby gets promoted. Real but adds wall-clock time to the smoke.
- **Multi-node kind** — current smoke runs on single-node kind (3 pods, 1 node). Anti-affinity-honoring multi-node would prove cross-node replication works, but adds CI time and a kind config variant.

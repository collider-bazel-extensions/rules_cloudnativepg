# Examples

Reference `Cluster` CRs for common shapes. Apply them after
`cloudnativepg_install` has the operator + CRDs running. None of these
require Bazel rules — they're plain YAML you can `kubectl apply` or pipe
through `rules_kubectl`'s `kubectl_apply` from any composition.

| File | Use case |
|---|---|
| [`single_instance.yaml`](single_instance.yaml) | Smallest viable Cluster — 1 instance. Compare with [`rules_pg`](https://github.com/collider-bazel-extensions/rules_pg) (single-node Postgres without an operator). |
| [`ha_cluster.yaml`](ha_cluster.yaml) | 3-instance HA with streaming replication + pod anti-affinity. The value-add CNPG provides over `rules_pg`. |
| [`with_cert_manager_tls.yaml`](with_cert_manager_tls.yaml) | Cluster consuming a cert-manager-issued postgres server cert. Pairs `rules_certmanager` + `rules_cloudnativepg`. |

To exercise an example end-to-end as a Bazel test, the canonical
composition is the in-tree smoke at `tests/BUILD.bazel`:
`kind_svc → cnpg_svc → service_test`. Copy the macro shape into your
own `tests/BUILD.bazel` and swap in your Cluster CR.

## Things this directory deliberately does NOT show

- **Backups** (`Backup`/`ScheduledBackup` CRs). Need an S3-compatible
  bucket; out of scope for v0.1.
- **Pooler** (PgBouncer connection pooling). v0.1 doesn't include a
  smoke target for this; consumers can author the YAML.
- **`Publication` / `Subscription` CRs** (logical replication). Same.

These are all CRs the operator already manages — `kubectl_apply` them
from your own composition without any special rule support.

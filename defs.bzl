"""Public API for rules_cloudnativepg.

Two macros that wrap rules_kubectl's `kubectl_apply` /
`kubectl_apply_health_check` with CNPG-operator-specific defaults: the
namespace, the per-version pre-rendered manifest, and the right wait
shape (the operator Deployment + the Cluster CRD).

The rule installs ONLY the operator. Cluster CRs (the actual postgres
clusters) are consumer-authored YAML — see README "Defining Clusters"
and `examples/`. Bazel-shaped Cluster rules are deferred to a future
release.
"""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")

# Map operator version → committed manifest label. Matches the entries
# in `tools/versions.bzl::CNPG_CHART_VERSIONS`.
_MANIFEST_BY_VERSION = {
    "0.27.1": "@rules_cloudnativepg//private/manifests:cloudnativepg-0.27.1.yaml",
    "0.28.0": "@rules_cloudnativepg//private/manifests:cloudnativepg-0.28.0.yaml",
}

# Latest stable. Default for `cloudnativepg_install(...)` if no
# `operator_version` is passed.
DEFAULT_OPERATOR_VERSION = "0.28.0"

# Names the operator's Deployment + the Cluster CRD register under.
# The chart names the Deployment `<release>-<chart>` — with our render
# release name `cnpg`, that's `cnpg-cloudnative-pg`. The CRD is the one
# we wait on before declaring the install done; without this wait,
# downstream services applying Cluster CRs would race the operator.
_CNPG_DEPLOY = "cnpg-cloudnative-pg"
_CNPG_CLUSTER_CRD = "clusters.postgresql.cnpg.io"

def _resolve_manifest(version):
    if version not in _MANIFEST_BY_VERSION:
        fail("rules_cloudnativepg: unsupported operator_version '{}'. Supported: {}".format(
            version, sorted(_MANIFEST_BY_VERSION.keys()),
        ))
    return _MANIFEST_BY_VERSION[version]

def cloudnativepg_install(
        name,
        operator_version = DEFAULT_OPERATOR_VERSION,
        namespace = "cnpg-system",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned CNPG operator manifest into `namespace`.

    Blocks until the operator Deployment is Available AND the
    `clusters.postgresql.cnpg.io` CRD is registered before idling.
    Without the CRD wait, downstream services that apply Cluster CRs
    immediately after install would race the operator's CRD installer.

    Args:
      name: target name.
      operator_version: which CNPG operator version to install. Must be
        one of the versions whose manifest is committed under
        `private/manifests/`. See module's `cnpg_chart.version()` tags.
      namespace: target namespace. Pre-created idempotently. Default
        `cnpg-system`.
      wait_timeout: timeout for the readiness waits.
      **kwargs: forwarded to `kubectl_apply` (e.g. `tags`,
        `kubeconfig_env`, extra `wait_for_*` lists).
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply(
        name = name,
        manifests = [_resolve_manifest(operator_version)],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_deployments = [_CNPG_DEPLOY] + list(extra_deploys),
        wait_for_crds = [_CNPG_CLUSTER_CRD] + list(extra_crds),
        wait_timeout = wait_timeout,
        **kwargs
    )

def cloudnativepg_health_check(
        name,
        namespace = "cnpg-system",
        **kwargs):
    """Readiness probe paired with `cloudnativepg_install`.

    Drops into `itest_service.health_check`. Re-runs the operator
    Deployment + Cluster CRD checks at itest's polling cadence.
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_deployments = [_CNPG_DEPLOY] + list(extra_deploys),
        wait_for_crds = [_CNPG_CLUSTER_CRD] + list(extra_crds),
        **kwargs
    )

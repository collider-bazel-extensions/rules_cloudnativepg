"""Maintainer-side: chart .tgz pins for each supported operator version.

Consumers don't see this — it's loaded only by the dev-only chart-fetch
extension under tools/. The committed manifests at
`//private/manifests:cloudnativepg-<ver>.yaml` are what consumers consume.

To support a new operator version:
  1. Add an entry below with chart_url + chart_sha256.
  2. Add the matching `helm_template` + `sh_binary` block in tools/BUILD.bazel.
  3. Add a `cnpg_chart.version()` tag and `use_repo` entry in MODULE.bazel.
  4. Add the version to `_MANIFEST_BY_VERSION` in defs.bzl.
  5. Add the manifest filegroup + label to `private/manifests/BUILD.bazel`.
  6. `bash tools/render_cnpg.sh <version>` (writes the manifest).
"""

CNPG_CHART_VERSIONS = {
    "0.27.1": {
        "chart_url":    "https://github.com/cloudnative-pg/charts/releases/download/cloudnative-pg-v0.27.1/cloudnative-pg-0.27.1.tgz",
        "chart_sha256": "67d7189f93219d355630ff7690169121cf606e67ac84abe05c53f88788de9d49",
    },
    "0.28.0": {
        "chart_url":    "https://github.com/cloudnative-pg/charts/releases/download/cloudnative-pg-v0.28.0/cloudnative-pg-0.28.0.tgz",
        "chart_sha256": "81d37894f3606df9bd91c5519053f41a79e833d28aca252ffb39294cb9cb19ae",
    },
}

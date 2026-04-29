#!/usr/bin/env bash
# tools/render_cnpg.sh — thin shim around the Bazel-native render flow.
#
# Maintainer flow:
#   1. Edit tools/versions.bzl::CNPG_CHART_VERSIONS to add/change the
#      entry, including chart_url + chart_sha256.
#   2. Add (or update) a `helm_template` + `sh_binary` block in
#      tools/BUILD.bazel for the new version.
#   3. Add a `cnpg_chart.version()` tag and `use_repo` entry in
#      MODULE.bazel.
#   4. Add the version → manifest mapping in defs.bzl.
#   5. Add the manifest filegroup + label in private/manifests/BUILD.bazel.
#   6. Run this script:
#          bash tools/render_cnpg.sh <chart-version>
set -euo pipefail

VERSION="${1:?usage: tools/render_cnpg.sh <chart-version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_cnpg] $TARGET"
exec bazel run "$TARGET"

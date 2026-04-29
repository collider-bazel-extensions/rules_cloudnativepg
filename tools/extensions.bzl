"""Maintainer-only chart fetch — fires only when rules_cloudnativepg is the root."""

load("//tools:repositories.bzl", "cnpg_chart_repository")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            cnpg_chart_repository(
                name = "cnpg_chart_" + tag.version.replace(".", "_"),
                version = tag.version,
            )

cnpg_chart = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)

"""Macros for the per-version default-smoke composition.

Bazel doesn't allow `def` in BUILD files; this is the Starlark module
that holds the macro the BUILD calls.
"""

load("@rules_cloudnativepg//:defs.bzl", "cloudnativepg_health_check", "cloudnativepg_install")
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

def _slug(v):
    return v.replace(".", "_")

def cnpg_default_smoke(version, kind_svc):
    """Wires the default smoke for one operator version: install rule,
    wrappers, itest_service, sh_test, service_test.

    Generates targets:
      :cnpg_install_<slug>_bin
      :cnpg_health_<slug>_bin
      :cnpg_install_<slug>_wrapper
      :cnpg_health_<slug>_wrapper
      :cnpg_svc_<slug>
      :smoke_test_default_<slug>_bin
      :smoke_test_default_<slug>          ← the user-facing service_test
    """
    s = _slug(version)
    cloudnativepg_install(
        name = "cnpg_install_{}_bin".format(s),
        operator_version = version,
        tags = ["manual"],
    )
    cloudnativepg_health_check(
        name = "cnpg_health_{}_bin".format(s),
        tags = ["manual"],
    )
    sh_binary(
        name = "cnpg_install_{}_wrapper".format(s),
        srcs = ["install_wrapper.sh"],
        data = [":cnpg_install_{}_bin".format(s)],
        args = ["cnpg_install_{}_bin".format(s)],
    )
    sh_binary(
        name = "cnpg_health_{}_wrapper".format(s),
        srcs = ["health_wrapper.sh"],
        data = [":cnpg_health_{}_bin".format(s)],
        args = ["cnpg_health_{}_bin".format(s)],
    )
    itest_service(
        name = "cnpg_svc_{}".format(s),
        exe = ":cnpg_install_{}_wrapper".format(s),
        deps = [kind_svc],
        health_check = ":cnpg_health_{}_wrapper".format(s),
        tags = ["manual"],
    )
    sh_test(
        name = "smoke_test_default_{}_bin".format(s),
        srcs = ["smoke_test.sh"],
        data = ["cluster.yaml"],
        args = ["$(rootpath :cluster.yaml)"],
        tags = ["manual"],
    )
    service_test(
        name = "smoke_test_default_{}".format(s),
        services = [":cnpg_svc_{}".format(s)],
        test = ":smoke_test_default_{}_bin".format(s),
        tags = [
            "manual",
            "no-sandbox",
            "requires-network",
        ],
    )

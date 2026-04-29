"""Macros for the per-version default-smoke composition.

The wrapper-script bin names are baked at genrule time (sed-substituted
into install_wrapper.sh.tmpl / health_wrapper.sh.tmpl). itest_service
doesn't pass `args` from sh_binary's attr, so a parametrized wrapper
that reads $1 doesn't work in this exec path.
"""

load("@rules_cloudnativepg//:defs.bzl", "cloudnativepg_health_check", "cloudnativepg_install")
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

def _slug(v):
    return v.replace(".", "_")

def _wrapper_pair(slug, bin_name, kind, template):
    """Generate a per-version wrapper sh_binary by substituting the bin
    name into the template. `kind` is "install" or "health", used only
    for naming."""
    name = "cnpg_{}_{}_wrapper".format(kind, slug)
    sh_filename = "{}.sh".format(name)
    native.genrule(
        name = name + "_sh",
        srcs = [template],
        outs = [sh_filename],
        cmd = "sed 's|__BIN_NAME__|{}|g' $< > $@".format(bin_name),
    )
    sh_binary(
        name = name,
        srcs = [":" + sh_filename],
        data = [":" + bin_name],
    )

def cnpg_default_smoke(version, kind_svc):
    """Wires the default smoke for one operator version.

    Generates the install + health bins, the per-version wrapper
    sh_binaries (with the bin name baked in via genrule), the
    itest_service, the sh_test, and the user-facing service_test.
    """
    s = _slug(version)
    install_bin = "cnpg_install_{}_bin".format(s)
    health_bin = "cnpg_health_{}_bin".format(s)

    cloudnativepg_install(
        name = install_bin,
        operator_version = version,
        tags = ["manual"],
    )
    cloudnativepg_health_check(
        name = health_bin,
        tags = ["manual"],
    )
    _wrapper_pair(s, install_bin, "install", "install_wrapper.sh.tmpl")
    _wrapper_pair(s, health_bin, "health", "health_wrapper.sh.tmpl")

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

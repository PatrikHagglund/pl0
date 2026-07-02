"""Repository rules for Koka toolchain."""

# Unofficial fork build: koka dev 3.2.7 + two optimizer fixes (specialize
# infinite loop, upstream PR #899; case-of-case exponential core blow-up,
# upstream PR #902). These let //shared:efuzz compile at -O3 with specialization
# in ~60s, so the efuzz lvalue generator is re-enabled and --fno-specialize is
# dropped from //shared:efuzz. Built from PatrikHagglund/koka tag v3.2.7-pl0e-efuzz
# via its .github/workflows/bundle-pl0e.yaml (bundle layout identical to an
# upstream release). Once #899 AND #902 ship in an official koka release, revert
# to upstream: bump KOKA_VERSION and restore the koka-lang/koka release URL/sha.
KOKA_VERSION = "3.2.7-pl0e-efuzz"

KOKA_PLATFORMS = {
    "linux-x64": {
        "url": "https://github.com/PatrikHagglund/koka/releases/download/v3.2.7-pl0e-efuzz/koka-v3.2.7-linux-x64.tar.gz",
        "sha256": "19c8a662d3d7add71293d75bc610375c105cc55edd8e85ca97154aed06ac10b2",
        "exec_compat": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    },
}

def _koka_repo_impl(rctx):
    platform = None
    for p, info in KOKA_PLATFORMS.items():
        if rctx.os.name.lower().startswith("linux") and rctx.os.arch == "amd64":
            platform = p
            break

    if not platform:
        fail("Unsupported platform: {} {}".format(rctx.os.name, rctx.os.arch))

    info = KOKA_PLATFORMS[platform]

    # Optional local override (NON-HERMETIC): point KOKA_LOCAL_PATH at a koka
    # binary (e.g. a cabal/stack dev build) to test compiler fixes before
    # they ship in a release. A dev-build binary locates its stdlib from its
    # own source tree, so only the binary is symlinked; the stdlib is
    # compiled on the fly per build (slower, fine for testing). Use via
    # `--config=koka-local` (see .bazelrc).
    local = rctx.os.environ.get("KOKA_LOCAL_PATH", "")
    if local:
        rctx.symlink(local, "bin/koka")
        rctx.file("BUILD.bazel", """
load("@rules_koka//koka:defs.bzl", "koka_toolchain")

exports_files(["bin/koka"])

filegroup(
    name = "koka_files",
    srcs = ["bin/koka"],
    visibility = ["//visibility:public"],
)

koka_toolchain(
    name = "toolchain_impl",
    koka = "bin/koka",
    koka_files = ":koka_files",
    version = "local",
)

toolchain(
    name = "toolchain",
    toolchain = ":toolchain_impl",
    toolchain_type = "@rules_koka//koka:toolchain_type",
    exec_compatible_with = {exec_compat},
)
""".format(exec_compat = info["exec_compat"]))
        return

    url = info["url"].format(version = rctx.attr.version)

    rctx.download_and_extract(url = url, sha256 = info["sha256"])

    rctx.file("BUILD.bazel", """
load("@rules_koka//koka:defs.bzl", "koka_toolchain")

exports_files(["bin/koka"])

filegroup(
    name = "koka_files",
    srcs = glob(["bin/**", "lib/**", "share/**"]),
    visibility = ["//visibility:public"],
)

koka_toolchain(
    name = "toolchain_impl",
    koka = "bin/koka",
    koka_files = ":koka_files",
    version = "{version}",
)

toolchain(
    name = "toolchain",
    toolchain = ":toolchain_impl",
    toolchain_type = "@rules_koka//koka:toolchain_type",
    exec_compatible_with = {exec_compat},
)
""".format(
        version = rctx.attr.version,
        exec_compat = info["exec_compat"],
    ))

_koka_repo = repository_rule(
    implementation = _koka_repo_impl,
    attrs = {"version": attr.string(default = KOKA_VERSION)},
    environ = ["KOKA_LOCAL_PATH"],
)

def _koka_ext_impl(mctx):
    for mod in mctx.modules:
        for cfg in mod.tags.toolchain:
            _koka_repo(name = cfg.name, version = cfg.version)

_toolchain_tag = tag_class(attrs = {
    "name": attr.string(default = "koka"),
    "version": attr.string(default = KOKA_VERSION),
})

koka_ext = module_extension(
    implementation = _koka_ext_impl,
    tag_classes = {"toolchain": _toolchain_tag},
)

def koka_register(name = "koka", version = KOKA_VERSION):
    """Macro for WORKSPACE users (non-bzlmod)."""
    _koka_repo(name = name, version = version)
    native.register_toolchains("@{}//:toolchain".format(name))

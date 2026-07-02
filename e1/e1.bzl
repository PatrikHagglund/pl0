load("@rules_cc//cc:defs.bzl", "cc_binary")

# Macro for compiling e1 source to native binary via C++ backend.
def e1_cpp_binary(name, src):
    native.genrule(
        name = name + "_cpp_gen",
        srcs = [src],
        outs = [name + ".cpp"],
        cmd = "$(location //e1:e1_compile) $< > $@",
        tools = ["//e1:e1_compile"],
    )
    cc_binary(
        name = name,
        srcs = [name + ".cpp"],
        deps = ["//e1:e1_hdrs"],
        includes = ["e1"],  # For finding headers
        copts = ["-I.", "-Ie1"],  # Additional include paths
        visibility = ["//visibility:public"],
    )

# Macro for compiling e1 source to native binary via LLVM backend.
# Uses llvm-link to merge IR files before clang -O3, enabling cross-module optimization.
# Note: -march=native is used here (final link step), but NOT in e1_rt_bigint_ll (IR generation)
# because CPU-specific intrinsics in IR prevent optimization when linked (2x slowdown).
def e1_llvm_binary(name, src):
    native.genrule(
        name = name + "_ll_gen",
        srcs = [src],
        outs = [name + ".ll"],
        cmd = "$(location //e1:e1_compile) --llvm $< > $@",
        tools = ["//e1:e1_compile"],
        visibility = ["//visibility:public"],
    )
    native.genrule(
        name = name,
        srcs = [name + ".ll", "//e1:e1_rt_bigint_ll"],
        outs = [name + "_bin"],
        cmd = """
            CRT_DIR=$(execpath @toolchains_llvm_bootstrapped//runtimes:crt_objects_directory_linux)
            GLIBC_LIB=$(execpath @toolchains_llvm_bootstrapped//runtimes/glibc:glibc_library_search_directory)
            RESOURCE_DIR=$(execpath @toolchains_llvm_bootstrapped//runtimes:resource_directory)
            $(execpath @llvm_tools_llvm//:bin/llvm-link) -S $(SRCS) -o $@.linked.ll
            $(execpath @toolchains_llvm_bootstrapped//tools:clang) -Wno-override-module -O3 -march=native \
                -target x86_64-linux-gnu \
                --sysroot=/dev/null \
                -fuse-ld=lld \
                -rtlib=compiler-rt \
                -resource-dir "$$RESOURCE_DIR" \
                -B"$$CRT_DIR" \
                -L"$$GLIBC_LIB" \
                -Wl,--push-state -Wl,--as-needed -lpthread -ldl -Wl,--pop-state \
                $@.linked.ll -o $@
            rm -f $@.linked.ll
        """,
        tools = [
            "@llvm_tools_llvm//:bin/llvm-link",
            "@toolchains_llvm_bootstrapped//tools:clang",
            "@toolchains_llvm_bootstrapped//runtimes:crt_objects_directory_linux",
            "@toolchains_llvm_bootstrapped//runtimes/glibc:glibc_library_search_directory",
            "@toolchains_llvm_bootstrapped//runtimes:resource_directory",
        ],
        executable = True,
        local = True,
        visibility = ["//visibility:public"],
    )

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("//cuda/private:action_names.bzl", "ACTION_NAMES")
load("//cuda/private:artifact_categories.bzl", "ARTIFACT_CATEGORIES")
load("//cuda/private:providers.bzl", "CudaToolchainConfigInfo")
load("//cuda/private:toolchain.bzl", "use_cpp_toolchain")
load(
    "//cuda/private:toolchain_config_lib.bzl",
    "action_config",
    "artifact_name_pattern",
    "env_entry",
    "env_set",
    "feature",
    "flag_group",
    "flag_set",
)

def _impl(ctx):
    artifact_name_patterns = [
        # artifact_name_pattern for object files
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.object_file,
            prefix = "",
            extension = ".o",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.pic_object_file,
            prefix = "",
            extension = ".pic.o",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.rdc_object_file,
            prefix = "",
            extension = ".rdc.o",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.rdc_pic_object_file,
            prefix = "",
            extension = ".rdc.pic.o",
        ),
        # artifact_name_pattern for static libraries
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.archive,
            prefix = "lib",
            extension = ".a",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.pic_archive,
            prefix = "lib",
            extension = ".pic.a",
        ),
    ]

    cc_toolchain = find_cpp_toolchain(ctx)

    nvcc_compile_env_feature = feature(
        name = "nvcc_compile_env",
        env_sets = [
            env_set(
                actions = [ACTION_NAMES.cuda_compile],
                env_entries = [env_entry("PATH", paths.dirname(cc_toolchain.compiler_executable))],
            ),
        ],
    )

    cuda_compile_action = action_config(
        action_name = ACTION_NAMES.cuda_compile,
        flag_sets = [
            flag_set(flag_groups = [
                flag_group(flags = ["-x", "cu"]),
                flag_group(
                    iterate_over = "arch_specs",
                    flag_groups = [
                        flag_group(
                            iterate_over = "arch_specs.stage2_archs",
                            flag_groups = [
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.virtual",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=compute_%{arch_specs.stage2_archs.arch}"],
                                ),
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.gpu",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=sm_%{arch_specs.stage2_archs.arch}"],
                                ),
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.lto",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=lto_%{arch_specs.stage2_archs.arch}"],
                                ),
                            ],
                        ),
                    ],
                ),
                flag_group(flags = ["-rdc=true"], expand_if_true = "use_rdc"),
            ]),
        ],
        implies = ["host_compiler_path", "include_paths", "defines", "host_defines", "compiler_input_flags", "compiler_output_flags", "nvcc_compile_env"],
    )

    cuda_device_link_action = action_config(
        action_name = ACTION_NAMES.device_link,
    )

    host_compiler_feature = feature(
        name = "host_compiler_path",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.cuda_compile],
                flag_groups = [flag_group(flags = ["-ccbin", "%{host_compiler}"])],
            ),
        ],
    )

    include_paths_feature = feature(
        name = "include_paths",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-I", "%{quote_include_paths}"],
                        iterate_over = "quote_include_paths",
                    ),
                    flag_group(
                        flags = ["-I", "%{include_paths}"],
                        iterate_over = "include_paths",
                    ),
                    flag_group(
                        flags = ["-isystem", "%{system_include_paths}"],
                        iterate_over = "system_include_paths",
                    ),
                ],
            ),
        ],
    )

    defines_feature = feature(
        name = "defines",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-D%{defines}"],
                        iterate_over = "defines",
                    ),
                ],
            ),
        ],
    )

    host_defines_feature = feature(
        name = "host_defines",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-D%{host_defines}"],
                        iterate_over = "host_defines",
                    ),
                ],
            ),
        ],
    )

    compiler_input_flags_feature = feature(
        name = "compiler_input_flags",
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [flag_group(flags = ["-c", "%{source_file}"])],
            ),
        ],
    )

    compiler_output_flags_feature = feature(
        name = "compiler_output_flags",
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [flag_group(flags = ["-o", "%{output_file}"])],
            ),
        ],
    )

    action_configs = [
        cuda_compile_action,
        cuda_device_link_action,
    ]

    features = [
        nvcc_compile_env_feature,
        host_compiler_feature,
        include_paths_feature,
        defines_feature,
        host_defines_feature,
        compiler_input_flags_feature,
        compiler_output_flags_feature,
    ]

    return [CudaToolchainConfigInfo(
        action_configs = action_configs,
        features = features,
        artifact_name_patterns = artifact_name_patterns,
        toolchain_identifier = ctx.attr.toolchain_identifier,
        cuda_path = ctx.attr.cuda_path,
    )]

cuda_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cuda_path": attr.string(default = "/usr/local/cuda"),
        "toolchain_identifier": attr.string(values = ["nvcc", "clang"], mandatory = True),
        "_cc_toolchain": attr.label(default = "@bazel_tools//tools/cpp:current_cc_toolchain"),  # legacy behaviour
    },
    provides = [CudaToolchainConfigInfo],
    toolchains = use_cpp_toolchain(),
)

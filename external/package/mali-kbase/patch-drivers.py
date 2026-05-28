import sys
import os

if len(sys.argv) < 2:
    print("Usage: patch-drivers.py <build_dir>")
    sys.exit(1)

build_dir = sys.argv[1]

# 1. Patch mali_kbase_core_linux.c
path1 = os.path.join(build_dir, "product/kernel/drivers/gpu/arm/midgard/mali_kbase_core_linux.c")
if os.path.exists(path1):
    with open(path1) as f:
        text1 = f.read()
    
    old1 = (
        "\t\t/* We recommend using Upper case for the irq names in dts, but if\n"
        "\t\t * there are devices in the world using Lower case then we should\n"
        "\t\t * avoid breaking support for them. So try using names in Upper case\n"
        "\t\t * first then try using Lower case names. If both attempts fail then\n"
        "\t\t * we assume there is no IRQ resource specified for the GPU.\n"
        "\t\t */\n"
        "\t\tirq = platform_get_irq_byname(pdev, irq_names_caps[i]);\n"
        "\t\tif (irq < 0) {\n"
        "\t\t\tstatic const char *const irq_names[] = { \"job\", \"mmu\", \"gpu\" };\n"
        "\n"
        "\t\t\tirq = platform_get_irq_byname(pdev, irq_names[i]);\n"
        "\t\t}\n"
        "\n"
        "\t\tif (irq < 0)"
    )
    new1 = "\t\tirq = platform_get_irq(pdev, i);\n\n\t\tif (irq < 0)"
    
    if old1 in text1:
        text1 = text1.replace(old1, new1)
        with open(path1, "w") as f:
            f.write(text1)
        print("mali_kbase_core_linux.c patched successfully.")
    elif "platform_get_irq(pdev, i)" in text1:
        print("mali_kbase_core_linux.c already patched.")
    else:
        # Let's try matching with space after tabs just in case
        old1_alt = (
            "\t\t/* We recommend using Upper case for the irq names in dts, but if\n"
            " \t\t * there are devices in the world using Lower case then we should\n"
            " \t\t * avoid breaking support for them. So try using names in Upper case\n"
            " \t\t * first then try using Lower case names. If both attempts fail then\n"
            " \t\t * we assume there is no IRQ resource specified for the GPU.\n"
            " \t\t */\n"
            " \t\tirq = platform_get_irq_byname(pdev, irq_names_caps[i]);\n"
            " \t\tif (irq < 0) {\n"
            " \t\t\tstatic const char *const irq_names[] = { \"job\", \"mmu\", \"gpu\" };\n"
            " \n"
            " \t\t\tirq = platform_get_irq_byname(pdev, irq_names[i]);\n"
            " \t\t}\n"
            " \n"
            " \t\tif (irq < 0)"
        )
        if old1_alt in text1:
            text1 = text1.replace(old1_alt, new1)
            with open(path1, "w") as f:
                f.write(text1)
            print("mali_kbase_core_linux.c patched successfully (alt).")
        else:
            sys.exit("ERROR: patch 1 target not found")
else:
    print(f"Skipping core patch (file not found): {path1}")

# 2. Patch mali_kbase_runtime_pm.c
path2 = os.path.join(build_dir, "product/kernel/drivers/gpu/arm/midgard/platform/devicetree/mali_kbase_runtime_pm.c")
if os.path.exists(path2):
    with open(path2) as f:
        text2 = f.read()
        
    if "#include <linux/delay.h>" not in text2:
        text2 = text2.replace("#include <linux/regulator/consumer.h>", "#include <linux/regulator/consumer.h>\n#include <linux/delay.h>\n#include <linux/reset.h>\n#include <linux/of.h>")
    
    old_pm = (
        "#ifdef KBASE_PM_RUNTIME\n"
        " \terror = pm_runtime_get_sync(kbdev->dev);\n"
        " \tif (error == 1) {\n"
        " \t\t/*\n"
        " \t\t * Let core know that the chip has not been\n"
        " \t\t * powered off, so we can save on re-initialization.\n"
        " \t\t */\n"
        " \t\tret = 0;\n"
        " \t}\n"
        " \tdev_dbg(kbdev->dev, \"pm_runtime_get_sync returned %d\\n\", error);\n"
        " #else\n"
        " \tenable_gpu_power_control(kbdev);\n"
        " #endif /* KBASE_PM_RUNTIME */\n"
        "\n"
        " #endif /* MALI_USE_CSF */\n"
        "\n"
        " \treturn ret;"
    )
    
    new_pm = (
        "#ifdef KBASE_PM_RUNTIME\n"
        " \terror = pm_runtime_get_sync(kbdev->dev);\n"
        " \tif (error == 1) {\n"
        " \t\t/*\n"
        " \t\t * Let core know that the chip has not been\n"
        " \t\t * powered off, so we can save on re-initialization.\n"
        " \t\t */\n"
        " \t\tret = 0;\n"
        " \t} else if (error < 0) {\n"
        " \t\tret = error;\n"
        " \t}\n"
        " \tdev_dbg(kbdev->dev, \"pm_runtime_get_sync returned %d\\n\", error);\n"
        " \tenable_gpu_power_control(kbdev);\n"
        " \tusleep_range(1000, 2000);\n"
        " #else\n"
        " \tenable_gpu_power_control(kbdev);\n"
        " #endif /* KBASE_PM_RUNTIME */\n"
        "\n"
        " #endif /* MALI_USE_CSF */\n"
        "\n"
        " \treturn ret;"
    )
    
    if old_pm in text2:
        text2 = text2.replace(old_pm, new_pm)
    elif "usleep_range(1000, 2000);" in text2:
        print("mali_kbase_runtime_pm.c PM already patched.")
    else:
        # Try alternate whitespace matching
        old_pm_alt = (
            "#ifdef KBASE_PM_RUNTIME\n"
            "\terror = pm_runtime_get_sync(kbdev->dev);\n"
            "\tif (error == 1) {\n"
            "\t\t/*\n"
            "\t\t * Let core know that the chip has not been\n"
            "\t\t * powered off, so we can save on re-initialization.\n"
            "\t\t */\n"
            "\t\tret = 0;\n"
            "\t}\n"
            "\tdev_dbg(kbdev->dev, \"pm_runtime_get_sync returned %d\\n\", error);\n"
            "#else\n"
            "\tenable_gpu_power_control(kbdev);\n"
            "#endif /* KBASE_PM_RUNTIME */\n"
            "\n"
            "#endif /* MALI_USE_CSF */\n"
            "\n"
            "\treturn ret;"
        )
        if old_pm_alt in text2:
            text2 = text2.replace(old_pm_alt, new_pm)
        else:
            sys.exit("ERROR: PM patch target not found")
            
    reset_block = (
        "static struct reset_control **gpu_resets;\n"
        "static int nr_gpu_resets;\n"
        "\n"
        "static int resets_init(struct kbase_device *kbdev)\n"
        "{\n"
        "\tstruct device_node *np;\n"
        "\tint i;\n"
        "\tint err = 0;\n"
        "\n"
        "\tnp = kbdev->dev->of_node;\n"
        "\n"
        "\tnr_gpu_resets = of_count_phandle_with_args(np, \"resets\", \"#reset-cells\");\n"
        "\tif (nr_gpu_resets <= 0) {\n"
        "\t\tdev_info(kbdev->dev, \"No resets found in dtb, skipping\\n\");\n"
        "\t\treturn 0;\n"
        "\t}\n"
        "\n"
        "\tgpu_resets = devm_kcalloc(kbdev->dev, (size_t)nr_gpu_resets, sizeof(*gpu_resets), GFP_KERNEL);\n"
        "\tif (!gpu_resets)\n"
        "\t\treturn -ENOMEM;\n"
        "\n"
        "\tfor (i = 0; i < nr_gpu_resets; ++i) {\n"
        "\t\tgpu_resets[i] = devm_reset_control_get_exclusive_by_index(kbdev->dev, i);\n"
        "\t\tif (IS_ERR(gpu_resets[i])) {\n"
        "\t\t\terr = PTR_ERR(gpu_resets[i]);\n"
        "\t\t\tnr_gpu_resets = i;\n"
        "\t\t\tbreak;\n"
        "\t\t}\n"
        "\t}\n"
        "\n"
        "\treturn err;\n"
        "}\n\n"
    )
    
    old_enable_start = "static void enable_gpu_power_control(struct kbase_device *kbdev)"
    if old_enable_start in text2 and "static struct reset_control **gpu_resets;" not in text2:
        text2 = text2.replace(old_enable_start, reset_block + old_enable_start)
        
    old_enable = (
        "static void enable_gpu_power_control(struct kbase_device *kbdev)\n"
        "{\n"
        "\tunsigned int i;\n"
        "\n"
        "#if defined(CONFIG_REGULATOR)\n"
        "\tfor (i = 0; i < kbdev->nr_regulators; i++) {\n"
        "\t\tif (kbdev->regulators[i])\n"
        "\t\t\tregulator_enable(kbdev->regulators[i]);\n"
        "\t}\n"
        "#endif\n"
        "\n"
        "\tfor (i = 0; i < kbdev->nr_clocks; i++) {\n"
        "\t\tif (kbdev->clocks[i])\n"
        "\t\t\tclk_prepare_enable(kbdev->clocks[i]);\n"
        "\t}\n"
        "}"
    )
    
    new_enable = (
        "static void enable_gpu_power_control(struct kbase_device *kbdev)\n"
        "{\n"
        "\tunsigned int i;\n"
        "\tint j;\n"
        "\n"
        "#if defined(CONFIG_REGULATOR)\n"
        "\tfor (i = 0; i < kbdev->nr_regulators; i++) {\n"
        "\t\tif (kbdev->regulators[i])\n"
        "\t\t\tregulator_enable(kbdev->regulators[i]);\n"
        "\t}\n"
        "#endif\n"
        "\n"
        "\tif (!gpu_resets)\n"
        "\t\tresets_init(kbdev);\n"
        "\n"
        "\tfor (j = 0; j < nr_gpu_resets; ++j) {\n"
        "\t\tif (gpu_resets[j])\n"
        "\t\t\treset_control_deassert(gpu_resets[j]);\n"
        "\t}\n"
        "\n"
        "\tudelay(10);\n"
        "\n"
        "\tfor (i = 0; i < kbdev->nr_clocks; i++) {\n"
        "\t\tif (kbdev->clocks[i])\n"
        "\t\t\tclk_prepare_enable(kbdev->clocks[i]);\n"
        "\t}\n"
        "}"
    )
    
    # Also support alternate whitespace matching
    old_enable_alt = (
        "static void enable_gpu_power_control(struct kbase_device *kbdev)\n"
        " {\n"
        " \tunsigned int i;\n"
        " \n"
        " #if defined(CONFIG_REGULATOR)\n"
        " \tfor (i = 0; i < kbdev->nr_regulators; i++) {\n"
        " \t\tif (kbdev->regulators[i])\n"
        " \t\t\tregulator_enable(kbdev->regulators[i]);\n"
        " \t}\n"
        " #endif\n"
        " \n"
        " \tfor (i = 0; i < kbdev->nr_clocks; i++) {\n"
        " \t\tif (kbdev->clocks[i])\n"
        " \t\t\tclk_prepare_enable(kbdev->clocks[i]);\n"
        " \t}\n"
        " }"
    )
    
    if old_enable in text2:
        text2 = text2.replace(old_enable, new_enable)
    elif old_enable_alt in text2:
        text2 = text2.replace(old_enable_alt, new_enable)
    elif "resets_init" in text2:
        print("mali_kbase_runtime_pm.c enable already patched.")
    else:
        sys.exit("ERROR: enable patch target not found")
        
    old_disable = (
        "static void disable_gpu_power_control(struct kbase_device *kbdev)\n"
        "{\n"
        "\tunsigned int i;\n"
        "\n"
        "\tfor (i = 0; i < kbdev->nr_clocks; i++) {\n"
        "\t\tif (kbdev->clocks[i])\n"
        "\t\t\tclk_disable_unprepare(kbdev->clocks[i]);\n"
        "\t}\n"
        "\n"
        "#if defined(CONFIG_REGULATOR)\n"
        "\tfor (i = 0; i < kbdev->nr_regulators; i++) {\n"
        "\t\tif (kbdev->regulators[i])\n"
        "\t\t\tregulator_disable(kbdev->regulators[i]);\n"
        "\t}\n"
        "#endif\n"
        "\n"
        "}"
    )
    
    new_disable = (
        "static void disable_gpu_power_control(struct kbase_device *kbdev)\n"
        "{\n"
        "\tunsigned int i;\n"
        "\tint j;\n"
        "\n"
        "\tfor (j = 0; j < nr_gpu_resets; ++j) {\n"
        "\t\tif (gpu_resets[j])\n"
        "\t\t\treset_control_assert(gpu_resets[j]);\n"
        "\t}\n"
        "\n"
        "\tudelay(10);\n"
        "\n"
        "\tfor (i = 0; i < kbdev->nr_clocks; i++) {\n"
        "\t\tif (kbdev->clocks[i])\n"
        "\t\t\tclk_disable_unprepare(kbdev->clocks[i]);\n"
        "\t}\n"
        "\n"
        "#if defined(CONFIG_REGULATOR)\n"
        "\tfor (i = 0; i < kbdev->nr_regulators; i++) {\n"
        "\t\tif (kbdev->regulators[i])\n"
        "\t\t\tregulator_disable(kbdev->regulators[i]);\n"
        "\t}\n"
        "#endif\n"
        "}"
    )
    
    old_disable_alt = (
        "static void disable_gpu_power_control(struct kbase_device *kbdev)\n"
        " {\n"
        " \tunsigned int i;\n"
        " \n"
        " \tfor (i = 0; i < kbdev->nr_clocks; i++) {\n"
        " \t\tif (kbdev->clocks[i])\n"
        " \t\t\tclk_disable_unprepare(kbdev->clocks[i]);\n"
        " \t}\n"
        " \n"
        " #if defined(CONFIG_REGULATOR)\n"
        " \tfor (i = 0; i < kbdev->nr_regulators; i++) {\n"
        " \t\tif (kbdev->regulators[i])\n"
        " \t\t\tregulator_disable(kbdev->regulators[i]);\n"
        " \t}\n"
        " #endif\n"
        " \n"
        " }"
    )
    
    if old_disable in text2:
        text2 = text2.replace(old_disable, new_disable)
    elif old_disable_alt in text2:
        text2 = text2.replace(old_disable_alt, new_disable)
    elif "reset_control_assert" in text2:
        print("mali_kbase_runtime_pm.c disable already patched.")
    else:
        sys.exit("ERROR: disable patch target not found")
        
    with open(path2, "w") as f:
        f.write(text2)
    print("mali_kbase_runtime_pm.c patched successfully.")
else:
    print(f"Skipping PM patch (file not found): {path2}")

print("mali-kbase patching completed.")

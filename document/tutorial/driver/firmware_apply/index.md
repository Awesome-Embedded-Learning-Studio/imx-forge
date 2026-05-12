<PageHeader icon="📦" title="固件应用" description="在 Linux 驱动中加载和使用固件文件" />

<ChapterNav variant="sub">
  <ChapterLink href="firmware" variant="sub">固件加载详解</ChapterLink>
</ChapterNav>

::: tip 学习目标
理解 Linux 固件加载机制，掌握 `request_firmware` API，能够在驱动中加载固件。
:::

::: details 快速示例
```c
#include <linux/firmware.h>

static int my_driver_probe(struct device *dev)
{
    const struct firmware *fw;
    int ret;

    ret = request_firmware(&fw, "my_firmware.bin", dev);
    if (ret) {
        dev_err(dev, "Failed to load firmware\n");
        return ret;
    }

    process_firmware(fw->data, fw->size);
    release_firmware(fw);
    return 0;
}
```

固件文件存放位置：`/lib/firmware/`
:::

<ChapterNav variant="sub">
  <ChapterLink href="../" variant="sub">← 返回驱动开发</ChapterLink>
</ChapterNav>

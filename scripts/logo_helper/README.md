# Logo Helper

自动将 PNG logo 转换为 BMP 格式并拷贝到 U-Boot 指定目录。

## 使用方法

```bash
# 使用默认配置（推荐）
./logo_helper.sh

# 自定义输出尺寸
./logo_helper.sh 800x480

# 完整自定义参数
./logo_helper.sh <尺寸> <输入PNG> <输出BMP>
./logo_helper.sh 800x480 custom/logo.png custom/output.bmp
```

## 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 尺寸 | `1024x600` | BMP 输出尺寸（强制缩放） |
| 输入 | `document/logo/logo.png` | 源 PNG 文件路径 |
| 输出 | `third_party/uboot-mainline/tools/logos/denx.bmp` | 目标 BMP 文件路径 |

## 依赖

- ImageMagick (`convert` 命令)

安装方法：
```bash
sudo apt install imagemagick
```

## 工作流程

1. 自动查找项目根目录
2. 读取 `document/logo/logo.png`
3. 转换为 BMP（去除 alpha 通道，8 位深度）
4. 拷贝到 U-Boot logos 目录
5. 清理临时文件

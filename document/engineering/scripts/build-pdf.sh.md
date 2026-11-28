# build-pdf.sh 说明文档

> **文件路径**: `scripts/build-pdf.sh`
> **脚本类型**: 固化入口（PDF 导出）
> **状态**: 稳定

## 概述

一键生成 IMX-Forge **整站教程**的单本 PDF,采用纯 Python 链路:**pandoc**(markdown → html5,带目录与代码高亮)+ **WeasyPrint**(html → pdf,CSS Paged Media)。


## 使用方法

```bash
# 基本用法(在仓库任意目录下均可,脚本会自动 cd 到仓库根)
./scripts/build-pdf.sh

# 本地免 root 运行(uv 负责按需拉取 Python 依赖)
uv run --no-project --with pypandoc-binary --with weasyprint \
  python3 scripts/build_pdf.py
```

> 说明:`build-pdf.sh` 自身不接受任何参数,它只是把所有命令行参数(`"$@"`)原样转发给 `build_pdf.py`;而 `build_pdf.py` 目前也无参数,行为由源码内的常量(输出路径、卷顺序、封面元信息等)决定。

## 参数说明

`build-pdf.sh` 不接受参数。脚本内部执行的命令:

| 命令片段 | 说明 |
|----------|------|
| `set -euo pipefail` | 严格模式:遇错即退出、未定义变量报错、管道任一环节失败即整体失败 |
| `cd "$(dirname "$0")/.."` | 切到仓库根目录,保证相对路径(`document/`、`scripts/`、`dist-pdf/`)正确 |
| `exec uv run --no-project --with pypandoc-binary --with weasyprint` | 用 `uv` 在隔离环境按需拉取依赖,`--no-project` 表示不依赖本项目的虚拟环境 |
| `python3 scripts/build_pdf.py "$@"` | 执行核心渲染脚本,转发额外参数 |

## 设计理念

1. **纯 Python 链路** — 仅靠 pandoc + WeasyPrint,绕开 VitePress / 网站 / Chromium,本地与 CI 行为一致且轻量。
2. **阅读顺序与网站同步** — 章节顺序复刻 `sidebar.ts`,调 `document/` 目录命名即可同时影响网站侧边栏与 PDF,单一数据源。
3. **入口与逻辑分离** — `build-pdf.sh` 只做固化入口(cd + uv 拉依赖 + exec),核心逻辑集中在 `build_pdf.py`,便于维护。
4. **CI 与发版解耦** — `pdf-export.yml` 手动触发、独立轻量 Release,不挂在 push/tag/release 上,不影响发版流水线。

## 更新日志

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-06-23 | 1.0 | 初始版本,补充完整说明(pandoc + WeasyPrint 整站 PDF 导出入口) |

---

> **文档生成时间**: 2026-06-23
> **对应提交**: `feat(pdf): add pandoc + WeasyPrint whole-site tutorial PDF export (#83)`

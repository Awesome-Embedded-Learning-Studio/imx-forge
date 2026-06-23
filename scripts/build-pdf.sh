#!/usr/bin/env bash
# 固化入口:一键生成 rk-forge 整站教程 PDF(纯 Python:pandoc + WeasyPrint)。
# 依赖由 uv 按需拉取(pypandoc-binary 内含 pandoc;weasyprint 需系统库 pango/cairo,
# 本机已装;CI 里由 workflow 的 apt 步骤安装)。
#
# 用法:  ./scripts/build-pdf.sh
set -euo pipefail
cd "$(dirname "$0")/.."
exec uv run --no-project --with pypandoc-binary --with weasyprint python3 scripts/build_pdf.py "$@"

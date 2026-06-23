#!/usr/bin/env python3
"""IMX-Forge 教程 → 单本 PDF(纯 Python)。

链路:pandoc(markdown → html5,带目录与代码高亮)+ WeasyPrint(html → pdf,CSS Paged Media)。
绕开 VitePress / 网站 / Chromium,直接渲染 document/ 下的 markdown 源为一本书。

章节阅读顺序复刻 site/.vitepress/config/sidebar.ts 的 sortEntries + LEARNING_ORDER + 卷顺序,
所以「想调顺序」= 改 document/ 里的目录名/数字前缀(与网站侧边栏一致),不用改本脚本。

用法(免 root):
  uv run --with pypandoc-binary --with weasyprint python3 scripts/build_pdf.py
"""
import re
import sys
from datetime import date
from pathlib import Path

import pypandoc
from weasyprint import HTML

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / 'document'
OUT = ROOT / 'dist-pdf' / 'imx-forge.pdf'
CSS_FILE = ROOT / 'scripts' / 'book.css'

# ── 封面元信息(固化在脚本顶部;纯 Python,不依赖 project.config.ts)────────────
META = {
    'eyebrow': 'IMX-Forge · 整站教程 PDF',
    'title': 'IMX-Forge 的教程文档',
    'subtitle': '专注于 IMX6ULL 的嵌入式 Linux 教程',
    'author': 'Awesome-Embedded-Learning-Studio · Charliechen',
}


def cover_html() -> str:
    """美化封面:眉题 / 书名 / 副标题 / 装饰线 / 作者 / 生成日期。"""
    return f"""
<section class="cover">
  <div class="cover-eyebrow">{META['eyebrow']}</div>
  <h1 class="cover-title">{META['title']}</h1>
  <div class="cover-sub">{META['subtitle']}</div>
  <div class="cover-rule"></div>
  <div class="cover-meta">
    <div class="cover-author">{META['author']}</div>
    <div class="cover-date">{date.today().isoformat()} 自动生成</div>
  </div>
</section>
"""

# 与 sidebar.ts 保持一致
LEARNING_ORDER = [
    'linux-basics', 'start', 'docker', 'uboot', 'kernel', 'rootfs',
    'driver', 'practical', 'flash', 'commands', 'build', 'third_party',
]
# 卷顺序遵循 project.config 里 sidebar.volumes 的定义
VOLUMES = [
    'tutorial', 'architecture', 'ci', 'scripts', 'development',
    'modules', 'release', 'team', 'notes', 'qa', 'todo',
]
VOLUME_TITLE = {
    'tutorial': '教程', 'architecture': '架构', 'ci': 'CI/CD', 'scripts': '脚本',
    'development': '开发', 'modules': '模块', 'release': '发布', 'team': '贡献者',
    'notes': '工程笔记', 'qa': 'QA', 'todo': '待办',
}
SKIP_ENTRIES = {'hooks', 'stylesheets', 'javascripts', 'images', 'logo', 'logs'}
SKIP_FILES = {'index.md', 'tags.md', 'README.md'}


def sort_key(name: str):
    """复刻 sidebar.ts 的 sortEntries:数字前缀优先 → LEARNING_ORDER → 字典序。"""
    m = re.match(r'^(\d+)', name)
    if m:
        return (0, int(m.group(1)), name)
    if name in LEARNING_ORDER:
        return (1, LEARNING_ORDER.index(name), name)
    return (2, 0, name)


def collect(dirpath: Path):
    """DFS 收集 .md,顺序同 sidebar.ts scanDir;目录自身的 index.md 排在该目录最前。"""
    ordered: list[Path] = []
    idx = dirpath / 'index.md'
    if idx.exists():
        ordered.append(idx)
    try:
        entries = [e for e in sorted(dirpath.iterdir(), key=lambda p: sort_key(p.name))
                   if not e.name.startswith('.') and e.name not in SKIP_ENTRIES]
    except FileNotFoundError:
        return ordered
    for e in entries:
        if e.name in SKIP_FILES:
            continue
        if e.is_dir():
            ordered.extend(collect(e))
        elif e.suffix == '.md':
            ordered.append(e)
    return ordered


def ordered_files():
    files: list[Path] = []
    for vol in VOLUMES:
        vdir = DOC / vol
        if vdir.exists():
            files.extend(collect(vdir))
    # 根级附录页(非首页/README),按名排序追加
    for md in sorted(DOC.glob('*.md'), key=lambda p: sort_key(p.stem)):
        if md.name in {'index.md', 'README.md'}:
            continue
        files.append(md)
    return files


# ── markdown 预处理:剥离 VitePress 专属语法,得到 pandoc 能干净处理的 md ──────────
VUE_WRAP_LINE = re.compile(
    r'^\s*</?(RoadMap|RoadMapPhase|PageHeader|HomeTipBanner|HomeArchDiagram|'
    r'DocNavCards|StatusTag|StepFlow|StepItem|InfoCard|ChapterNav|ChapterLink|Badge)\b[^>]*/?>\s*$')
CHAPTER_LINK = re.compile(r'<ChapterLink\b[^>]*>(.*?)</ChapterLink>', re.S)
RESIDUAL_COMP = re.compile(
    r'</?(RoadMap|RoadMapPhase|PageHeader|HomeTipBanner|HomeArchDiagram|'
    r'DocNavCards|StatusTag|StepFlow|StepItem|InfoCard|ChapterNav|Badge)\b[^>]*/?>')
FRONTMATTER = re.compile(r'\A---\n.*?\n---\s*\n', re.S)


def preprocess(md: str) -> str:
    md = FRONTMATTER.sub('', md, count=1)          # 去掉 YAML frontmatter
    lines = [ln for ln in md.splitlines() if not VUE_WRAP_LINE.match(ln)]
    md = '\n'.join(lines)
    md = CHAPTER_LINK.sub(lambda m: f'- {m.group(1).strip()}', md)  # ChapterLink → 列表项
    md = RESIDUAL_COMP.sub('', md)                                  # 残留组件标签
    return md


def main():
    files = ordered_files()
    if not files:
        sys.exit('未在 document/ 找到任何 markdown')
    print(f'按阅读顺序收集 {len(files)} 篇 markdown')

    vol_root = {vol: str((DOC / vol).resolve()) for vol in VOLUMES if (DOC / vol).exists()}
    current_vol = None
    parts = []
    for f in files:
        vol = next((v for v, root in vol_root.items() if str(f).startswith(root)), None)
        if vol != current_vol:
            current_vol = vol
            parts.append(f'\n\n<div class="part-break"></div>\n\n# {VOLUME_TITLE.get(vol, vol)}\n\n')
        else:
            parts.append('\n\n<div class="chapter-break"></div>\n\n')
        parts.append(preprocess(f.read_text(encoding='utf-8')))
    assembled = '\n'.join(parts)

    # pandoc:markdown → html5(目录、代码高亮、raw HTML 保留)
    html = pypandoc.convert_text(
        assembled, 'html5',
        format='markdown+raw_html+yaml_metadata_block+pipe_tables+auto_identifiers+fenced_divs',
        extra_args=[
            '--toc', '--toc-depth=3',
            '--highlight-style=tango',
            '--standalone',
            '--metadata', f'title={META["title"]}',
        ],
    )
    # 把我们的 CSS 挂进 standalone HTML 的 <head>
    css_link = f'<link rel="stylesheet" href="{CSS_FILE.as_uri()}">'
    html = html.replace('</head>', css_link + '</head>', 1)
    # 去掉 pandoc 默认的 <header> 标题块,改用美化封面
    html = re.sub(r'<header[^>]*>.*?</header>', '', html, count=1, flags=re.S)
    html = html.replace('<body>', '<body>' + cover_html(), 1)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    HTML(string=html, base_url=str(ROOT)).write_pdf(str(OUT), stylesheets=[str(CSS_FILE)])
    size = OUT.stat().st_size / 1e6
    print(f'✅ 已生成: {OUT}\n   体积 {size:.1f} MB')


if __name__ == '__main__':
    main()

import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

// VitePress config 在构建期的 Node 进程里运行(不受浏览器限制,Date 可用),
// 部署工作流 .github/workflows/deploy.yml 已 fetch-depth: 0,可零依赖拿到完整
// git 历史+tag。版本展示的唯一真相源是 git tag(package.json 的 version 是
// 停滞占位值 0.0.1,不可信)。

// 本文件位于 site/.vitepress/config/,仓库根在其上三级。显式钉死 git 的 cwd:
// package.json 的脚本今天从仓库根跑,但把仓库根算出来传进去后,无论进程从哪个
// 目录启动结果都一致,不依赖调用方的 cwd 约定。
const repoRoot = fileURLToPath(new URL('../../../', import.meta.url))

function git(args: string[]): string {
  try {
    return execFileSync('git', args, {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'], // git 告警别漏进 config 加载日志
    }).trim()
  } catch {
    return '' // 非 git 仓库 / 无 tag → 回退
  }
}

export interface BuildInfo {
  /** git describe 结果,如 v1.0.4 或 v1.0.4-3-gabc1234(-dirty 表示有未提交改动) */
  version: string
  /** 7 位短 SHA */
  sha: string
  /** 构建日期 YYYY-MM-DD */
  date: string
}

export function getBuildInfo(): BuildInfo {
  return {
    // --match 'v*' 只认发布版本 tag:本仓库 tag 池里混有 pdf 导出 tag(如 pdf/2026-06-23),
    // 裸 --tags 会就近匹配到它们,页脚会显示出版本号而不是发布号。
    version: git(['describe', '--tags', '--match', 'v*', '--always', '--dirty']) || 'dev',
    sha: git(['rev-parse', '--short=7', 'HEAD']),
    date: new Date().toISOString().substring(0, 10),
  }
}

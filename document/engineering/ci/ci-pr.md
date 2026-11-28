# PR Quick Checks

快速检查工作流，为每个 PR 提供快速的反馈。

## 文件

`.github/workflows/ci-pr.yml`

## 触发条件

| 事件 | 条件 |
|------|------|
| `pull_request` | PR 打开或更新到 main 分支 |
| `workflow_dispatch` | 手动触发 |

## 包含的 Jobs

### 1. Documentation - 文档验证

- 检查脚本 README 覆盖率 (`develop/scripts_readme_check.sh`)
- 验证 VitePress 文档站点能否正常构建

### 2. Shell Scripts - 脚本语法检查

- 使用 ShellCheck 检查所有 `.sh` 文件
- 扫描目录：`scripts/`

### 3. Configuration Files - 配置验证

- 检查 defconfig 模板文件存在性
- 验证设备树文件语法

### 4. Docker Environment - Docker 环境验证

- 构建 Docker 镜像
- 验证 ARM 工具链可用

## 预计时间

| Job | 时间 |
|-----|------|
| Documentation | ~1 分钟 |
| Shell Scripts | ~1 分钟 |
| Configuration Files | ~1 分钟 |
| Docker Environment | ~3 分钟 |

**总计**：约 5-6 分钟（所有 Job 并行运行）

## 失败处理

- **ShellCheck**：警告级别不会导致失败
- **其他 Job**：失败会阻止 PR 合并

## 并发控制

使用 `cancel-in-progress: true`，PR 更新时会取消之前的运行。

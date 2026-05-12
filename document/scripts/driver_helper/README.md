# 驱动开发基建系统文档

> **欢迎！** 这里是IMX-Forge驱动开发基建系统的完整文档。

## 📚 文档导航

### 快速开始

- **[系统总览](overview.md)** - 5分钟了解基建系统
- **[快速开始指南](overview.md#快速开始)** - 第一次使用？从这里开始

### 核心文档

- **[完整工作流程](workflow.md)** - 按场景学习使用方法
- **[架构设计原理](architecture.md)** - 深入理解系统设计

### 脚本参考

- **[构建脚本](build_driver.md)** - build_driver.sh详解
- **[部署脚本](deploy_driver.md)** - deploy_driver.sh详解
- **[审查脚本](review_driver.md)** - review_driver.sh详解
- **[设备树脚本](show_device_tree.md)** - show_device_tree.sh详解
- **[配置文件](configuration.md)** - driver_helper.conf详解
- **[构建库](../lib/driver_buildlib.md)** - driver_buildlib.sh详解

### 实践指南

- **[example_driver验证](../examples/example_driver.md)** - 验证步骤和命令清单
- **[错误排查指南](troubleshooting.md)** - 常见问题和解决方案
- **[最佳实践](best_practices.md)** - 开发流程和工作技巧

### 相关文档

- **设备树编译机制** - 内核如何处理设备树编译
- **设备树编译迁移** - 我们的设备树编译实现

## 🎯 按角色阅读

### 新手驱动开发者

推荐阅读顺序：
1. [系统总览](overview.md) - 了解系统
2. [快速开始](overview.md#快速开始) - 动手实践
3. [工作流程](workflow.md) - 学习完整流程
4. [example_driver验证](../examples/example_driver.md) - 验证你的环境

### 有经验的驱动开发者

推荐阅读顺序：
1. [系统总览](overview.md) - 快速了解
2. [脚本参考](./overview.md) - 按需查阅
3. [架构设计](architecture.md) - 深入理解

### 项目维护者

推荐阅读顺序：
1. [架构设计](architecture.md) - 理解设计原理
2. 设备树编译机制 - 内核机制
3. 设备树编译迁移 - 迁移实现
4. [最佳实践](best_practices.md) - 维护建议

### 快速上手用户

只需要：
1. [快速开始](overview.md#快速开始) - 5分钟上手
2. [脚本参考](./overview.md) - 需要时查阅

## 📖 文档约定

### 符号说明

- `⭐` - 重要内容
- `✅` - 最佳实践
- `❌` - 不推荐做法
- `⚠️` - 注意事项
- `💡` - 技巧提示

### 代码块

```bash
# Shell命令
$ ./scripts/driver_helper/build_driver.sh example-driver
```

```c
// C代码
int example_function() {
    return 0;
}
```

```dts
// 设备树
/ {
    node {
        compatible = "example";
    };
};
```

### 难度级别

- 🟢 初级 - 适合新手
- 🟡 中级 - 需要一些基础
- 🔴 高级 - 需要深入理解

## 🔗 相关资源

### 项目链接

- **项目根目录**：[../../](../../)
- **驱动脚本**：`scripts/driver_helper/`
- **示例驱动**：`driver/example-driver/`
- **配置文件**：[../../scripts/driver_helper/driver_helper.conf](../../scripts/driver_helper/driver_helper.conf)

### 外部资源

- [Linux内核文档](https://www.kernel.org/doc/html/latest/)
- [设备树规范](https://www.devicetree.org/)
- [i.MX6ULL参考手册](https://www.nxp.com/docs/en/reference-manual/IMX6ULLRM.pdf)

## 🆘 获取帮助

### 遇到问题？

1. 查看[错误排查指南](troubleshooting.md)
2. 搜索[GitHub Issues](https://github.com/your-repo/issues)
3. 提问时提供：
   - 使用的命令
   - 错误信息
   - 系统环境

### 贡献文档

发现文档错误或有改进建议？欢迎：
- 修改文档直接提交PR
- 提出Issue讨论
- 在Issue中提问

---

**快速开始？** → [系统总览](overview.md)

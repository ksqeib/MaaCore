# MaaCore (upstream sync mirror)

本仓库现在只负责同步上游 MaaCore：

- .github/workflows/sync_upstream_core.yml 每天从 MaaAssistantArknights/MaaAssistantArknights 的 dev-v2 提取 src/MaaCore，推送到 upstream-sync 分支。
- 不保存独立构建脚本，也不在这里发布 SDK。

构建、依赖组装、nightly 发布请使用：

https://github.com/ksqeib/MaaCoreBuild
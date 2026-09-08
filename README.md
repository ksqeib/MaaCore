# MaaCore

MAA 底层 C++ 模块

## 单仓库独立构建（Windows）

目标仅生成 `MaaCore.dll` 与对应调试符号 `MaaCore.pdb`，不依赖父仓库构建流程。

### 1) 初始化子模块

```powershell
git submodule update --init --recursive MaaUtils
```

### 2) 准备独立构建依赖（本仓库头文件 + MaaDeps）

头文件目录约定：

- `include/upstream`：对外 API 头（来自主仓库 `include`）
- `include/3rd`：编译所需第三方头（来自主仓库 `3rdparty/include`）

如需同步更新头文件：

```powershell
powershell -File .\tools\sync-includes.ps1
```

```powershell
powershell -File .\tools\bootstrap-standalone.ps1
```

该脚本会：

- 初始化 `MaaUtils` 子模块
- 校验本仓库 `include/upstream` 与 `include/3rd` 关键头文件存在
- 下载 MaaDeps 到 `MaaUtils/MaaDeps`

### 3) 编译 MaaCore

```powershell
powershell -File .\tools\build-maacore-only.ps1
```

可选：启用 `sccache` 加速重复编译。

```powershell
powershell -File .\tools\build-maacore-only.ps1 -UseSccache -NoFresh
```

`-Parallel` 默认为 `0`，表示自动使用当前机器的逻辑处理器数量。若本机或 CI 内存压力较大，可以手动限制，例如 `-Parallel 4`。

启用 `sccache` 时脚本会使用 `Ninja Multi-Config`，因为 Visual Studio `.vcxproj` 生成器不会可靠地使用 `CMAKE_C_COMPILER_LAUNCHER` / `CMAKE_CXX_COMPILER_LAUNCHER`。如果现有 `build-standalone` 是 Visual Studio 生成器配置出来的，脚本会自动清理旧构建目录并重新配置一次。

`sccache` 模式还会把 MSVC 编译期调试信息切换为 `/Z7`，避免 `/Zi` 共享编译 PDB 与 `sccache` 并发缓存冲突；最终链接产物仍会生成 `MaaCore.pdb`。

脚本同时会关闭 C++20 module 依赖扫描（`CMAKE_CXX_SCAN_FOR_MODULES=OFF`）。当前目标只是生成 `MaaCore.dll` / `MaaCore.pdb`，且项目未按 C++ modules 组织源码；关闭该扫描可以减少大量不可缓存的 MSVC `-scanDependencies` 开销。

产物默认输出到：

- `build-standalone/bin/RelWithDebInfo/MaaCore.dll`
- `build-standalone/bin/RelWithDebInfo/MaaCore.pdb`

### 依赖引用说明

- `docs/compile/maacore-standalone-dependency-notes.md`

### 维护规则

- `agent.md`

## GitHub CI 产物下载

- 工作流文件：`.github/workflows/maacore-build.yml`
- 触发方式：`push` 到 `main`、`pull_request`、手动 `workflow_dispatch`
- `workflow_dispatch` 可选构建配置：`Debug`（默认，速度更快）或 `RelWithDebInfo`
- `workflow_dispatch` 可选构建并发：`0` 表示自动使用 GitHub runner 的逻辑处理器数量，也可以手动指定
- CI 已启用 `sccache`（重复构建更快），可在日志中查看 `sccache --show-stats`
- CI 仅构建并上传：`MaaCore.dll`、`MaaCore.pdb`
- 不创建 Release，可在 Actions 页面直接下载 Artifact：`MaaCore-windows-x64-<Config>`

## 本机启用 sccache

```powershell
winget install --id Mozilla.sccache -e
```

安装后验证：

```powershell
sccache --version
```

查看命中率：

```powershell
sccache --show-stats
```

推荐本机命令：

```powershell
Set-Location "D:\self\maa\MaaCore"
sccache --zero-stats
powershell -ExecutionPolicy Bypass -File ".\tools\build-maacore-only.ps1" -SkipBootstrap -UseSccache -NoFresh
sccache --show-stats
```


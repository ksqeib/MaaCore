# MaaCore

MAA 底层 C++ 模块。

## 单仓库独立构建（Windows）

目标：产出 `MaaCore.dll` / `MaaCore.pdb`，并可打成供其他启动器集成的 SDK 包，不依赖父仓库构建流程。

### 1) 准备依赖

依赖来源只有两处：

- **入库跟踪**：`include/upstream`（对外 API 头）、`include/3rd`（头文件型第三方库）、`MaaUtils/`（源码，随工程编译）
- **下载得到**：`deps/`（OpenCV / ONNXRuntime / Boost / zlib 来自官方固定 URL，FastDeploy 来自一个小型发布包）

不再使用 `MaaUtils/MaaDeps` 子模块，也不再应用 MaaDeps 的自定义 patch：

```powershell
powershell -File .\tools\bootstrap-standalone.ps1
```

首次运行会：

1. 从 `tools/deps-manifest.json` 下载约 15 MB 的 FastDeploy 包（含 `DirectML.dll`）
2. 从官方固定 URL 下载 OpenCV 4.12.0、ONNXRuntime 1.19.2 DirectML、Boost 1.89、zlib 1.3.1（约 400 MB，缓存到 `.bootstrap/upstream-deps`）
3. 本地编译 Boost.Regex 与 zlib
4. 组装 `deps/`

`deps/` 不入库；后续构建直接复用，不会重复下载/编译。

如需同步 `include/` 头文件：

```powershell
powershell -File .\tools\sync-includes.ps1
```

> 机制说明见 `docs/remove-maadeps.md`，依赖引用见 `docs/compile/maacore-standalone-dependency-notes.md`。

如需强制从官方发布物重新生成 `deps/`：

```powershell
powershell -File .\tools\fetch-deps.ps1 -Force
# 或
powershell -File .\tools\build-upstream-deps.ps1
```

脚本会下载/复用官方包，编译 Boost.Regex 与 zlib，并从官方 DLL 生成 `_maa` 命名导入库。FastDeploy 默认来自现有 `deps/` 或 `tools/deps-manifest.json` 指向的小包。

### 2) 编译 MaaCore

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

### 3) 打 SDK 发布包

```powershell
powershell -File .\tools\package-sdk.ps1 -Version v1.0.0
```

输出 `dist/MaaCore-sdk-windows-x64-v1.0.0.zip`，**zip 根目录直接是 `bin/` 和 `include/`**，不套版本目录：

```
bin/        MaaCore.dll / MaaCore.pdb / MaaUtils.dll / 运行时 DLL（OpenCV、ONNXRuntime、fastdeploy、DirectML）
include/    对外 API 头文件
README.md   集成说明
```

默认不包含 CUDA provider；需要时把 `onnxruntime_providers_cuda.dll` 放进 `deps/runtime/maa-x64-windows/` 再加 `-IncludeCuda`。`resource/` 由启动器自行分发，不打进 SDK。

### 维护 FastDeploy 包

OpenCV / ONNXRuntime / Boost / zlib 不再整包发布，bootstrap 时直接从官方 URL 下载。只有 FastDeploy 需要一个小的发布包：

```powershell
# 从现有 deps/ 提取 FastDeploy + DirectML，更新 tools/deps-manifest.json
powershell -File .\tools\pack-fastdeploy.ps1 -BundleVersion v1 -UpdateManifest
```

生成的 `dist/MaaCore-fastdeploy-windows-x64-v1.zip`（约 15 MB）上传到 tag 为 `fastdeploy-v1` 的 GitHub Release 即可。

### 依赖引用说明

- `docs/compile/maacore-standalone-dependency-notes.md`

### 维护规则

- `agent.md`

## GitHub CI

- 构建工作流：`.github/workflows/maacore-build.yml`（**仅手动 `workflow_dispatch`**；产物 artifact 为 `MaaCore.dll` + `MaaCore.pdb`）
- 发布工作流：`.github/workflows/maacore-release.yml`（打 `v*` tag 或手动指定版本；发布 SDK zip）
- 上游同步工作流：`.github/workflows/sync_upstream_core.yml`（**仅手动**，不再每日定时运行）
- 不再在 push / PR 时自动触发构建，避免消耗 Actions 配额
- CI 会同时缓存 `deps/` 和 `.bootstrap/upstream-deps`；首次未命中时自动下载官方包并编译 Boost.Regex / zlib
- CI 已启用 `sccache`，可在日志中查看 `sccache --show-stats`

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

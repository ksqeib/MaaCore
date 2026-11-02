# MaaCore

MAA 底层 C++ 模块。

## 单仓库独立构建（Windows）

目标：产出 `MaaCore.dll` / `MaaCore.pdb`，并可打成供其他启动器集成的 SDK 包，不依赖父仓库构建流程。

### 1) 准备依赖

依赖来源只有两处：

- **入库跟踪**：`include/upstream`（对外 API 头）、`include/3rd`（头文件型第三方库）、`MaaUtils/`（源码，随工程编译）
- **下载得到**：`deps/`（上游官方 OpenCV / ONNXRuntime / DirectML / Boost / zlib，以及 FastDeploy 预编译产物）

不再使用 `MaaUtils/MaaDeps` 子模块，也不再应用 MaaDeps 的自定义 patch。`deps/` 由 `tools/deps-manifest.json` 锚定版本与 SHA-256，通过 `tools/fetch-deps.ps1` 获取：

```powershell
powershell -File .\tools\bootstrap-standalone.ps1
```

脚本会校验本仓库头文件、下载并解压 `deps/`，然后做完整性检查。`deps/` 约 195 MB（压缩包），不入库。

如需同步 `include/` 头文件：

```powershell
powershell -File .\tools\sync-includes.ps1
```

> 机制说明见 `docs/remove-maadeps.md`，依赖引用见 `docs/compile/maacore-standalone-dependency-notes.md`。

如需从官方发布物重新生成 `deps/`：

```powershell
powershell -File .\tools\build-upstream-deps.ps1
```

脚本会下载官方 OpenCV 4.12.0、ONNXRuntime 1.19.2 DirectML、DirectML 1.15.4、Boost 1.89、zlib 1.3.1，编译 Boost.Regex 与 zlib，并从官方 DLL 生成 `_maa` 命名导入库。FastDeploy 会自动从现有 `deps/` 复用。

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

输出 `dist/MaaCore-sdk-windows-x64-v1.0.0.zip`，包含：

```
bin/        MaaCore.dll / MaaCore.pdb / MaaUtils.dll / 运行时 DLL（OpenCV、ONNXRuntime、fastdeploy、DirectML）
include/    对外 API 头文件
README.md   集成说明
```

默认不包含 CUDA provider；需要时把 `onnxruntime_providers_cuda.dll` 放进 `deps/runtime/maa-x64-windows/` 再加 `-IncludeCuda`。`resource/` 由启动器自行分发，不打进 SDK。

### 维护依赖包

```powershell
# 修改 deps/ 后重新打包，并更新 tools/deps-manifest.json 中的 URL / sha256
powershell -File .\tools\pack-deps.ps1 -BundleVersion v2 -UpdateManifest
```

生成的 `dist/MaaCore-deps-windows-x64-v2.zip` 上传到 tag 为 `deps-v2` 的 GitHub Release 即可。

### 依赖引用说明

- `docs/compile/maacore-standalone-dependency-notes.md`

### 维护规则

- `agent.md`

## GitHub CI

- 构建工作流：`.github/workflows/maacore-build.yml`（push 到 `main`/`dev`、PR、手动；产物 artifact 为 `MaaCore.dll` + `MaaCore.pdb`）
- 发布工作流：`.github/workflows/maacore-release.yml`（打 `v*` tag 或手动指定版本，自动构建并发布 SDK zip）
- 依赖包工作流：`.github/workflows/maacore-deps.yml`（打 `deps-v*` tag 或手动指定版本，自动组装官方依赖、发布 bundle，并提交更新后的 `tools/deps-manifest.json`）
- CI 已启用 `sccache`，可在日志中查看 `sccache --show-stats`
- 依赖包按 `tools/deps-manifest.json` 的哈希缓存；未命中时自动下载

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

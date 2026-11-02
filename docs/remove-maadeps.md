# 移除 MaaDeps 依赖（de-MaaDeps）

本文记录本仓库如何彻底脱离 `MaaUtils/MaaDeps` 子模块，以及现在依赖从哪里来、怎么发版。

## 结论速览

MaaDeps 本身不产出代码，它只是一个「从 GitHub Release 下载 vcpkg 预编译包，再把 CMake 的 `find_package` 指过去」的下载器。因此移除它不是让依赖消失，而是**换一个受控的二进制来源**：

| 项目 | 原来 | 现在 |
|---|---|---|
| 二进制依赖 | `MaaUtils/MaaDeps` 子模块内下载，约 3.6 GB | `deps/` 目录，由本仓库发布的一个约 130 MB 压缩包解压 |
| 依赖版本锚点 | git 子模块指针 | `tools/deps-manifest.json` 里的 URL + SHA-256 |
| MaaUtils | git 子模块，随工程从源码编译 | **源码 vendored 在 `MaaUtils/`，仍从源码编译** |
| 下载脚本 | `MaaUtils/tools/maadeps_download.py` | `tools/fetch-deps.ps1` |
| 发版产物 | 只有 CI artifact（`MaaCore.dll/pdb`） | SDK zip：`bin/` + `include/` + README |

## 目录与职责

```
deps/                        不入库；由 fetch-deps.ps1 解压得到
├── include/                 编译期头文件（OpenCV / ONNX / fastdeploy / Boost / zlib ...）
├── lib/                     链接库
├── bin/                     少量构建期 DLL
├── share/                   各库的 CMake config（135 个包）
├── debug/                   Debug 配置的 lib/bin
└── runtime/maa-x64-windows/ 运行时 DLL

MaaUtils/                    入库，源码
cmake/maadeps.cmake          入库，CMake 适配层（triplet + maadeps_install）
tools/
├── deps-manifest.json       依赖包清单（URL + sha256 + 版本）
├── fetch-deps.ps1           下载 / 校验 / 解压依赖包
├── pack-deps.ps1            把本地 deps/ 打成可发布压缩包
├── bootstrap-standalone.ps1 构建前统一入口
└── package-sdk.ps1          打 SDK 发布包
```

## 首次构建

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\bootstrap-standalone.ps1   # 下载 deps/
powershell -ExecutionPolicy Bypass -File .\tools\build-maacore-only.ps1 -SkipBootstrap -UseSccache -NoFresh
```

`fetch-deps.ps1` 的行为：

1. 读取 `tools/deps-manifest.json`，按当前平台选择 target（如 `windows-x64`）；
2. 命中 `deps/.bundle-version` 标记就直接返回；
3. 否则下载到 `.bootstrap/deps/`，校验 SHA-256 后解压到仓库根目录；
4. 解压后再校验 `include/`、`lib/`、`share/`、`runtime/maa-x64-windows/` 是否齐全。

## 依赖包怎么来、怎么更新

依赖包是从现有 MaaDeps v2.14.1 的产物里裁出来的最小集合，不是 vcpkg 现场构建：

```powershell
# 1) 准备好一份可用的 deps/（本地已有则跳过）
powershell -File .\tools\bootstrap-standalone.ps1

# 2) 打包；默认剔除 CUDA provider（约 170 MB），保留 DirectML
powershell -File .\tools\pack-deps.ps1 -UpdateManifest

# 3) 上传 dist/MaaCore-deps-windows-x64-v1.zip 到 tag 为 deps-v1 的 GitHub Release
#    （或 gh release create deps-v1 dist\MaaCore-deps-windows-x64-v1.zip ...）

# 4) 提交更新后的 tools/deps-manifest.json
```

`pack-deps.ps1` 使用固定时间戳和排序后的条目写 zip，**同一份输入会得到同一个 SHA-256**，便于校验。

升级依赖时：改 `-BundleVersion v2`、上传到 `deps-v2`、再 `-UpdateManifest`，最后提交 manifest。

## MaaUtils 为什么改回源码

上一版尝试把 `MaaUtils` 当预编译 DLL 消费，但会带来两个问题：

- 需要手工准备 `MaaUtils.dll/lib`，新克隆和 CI 都容易缺件；
- MaaCore 与 MaaUtils 的 ABI 需要人工对齐。

MaaUtils 源码只有约 300 KB，vendored 进来后 `add_subdirectory` 从源码编译，问题消失。它对依赖的要求仍然通过 `MAADEPS_DIR` 指向 `deps/`：

```cmake
set(MAADEPS_DIR "${PROJECT_SOURCE_DIR}/deps")
set(DEP_DEPS_DIR "${MAADEPS_DIR}")
set(MAA_DEPS_CONFIG "${PROJECT_SOURCE_DIR}/cmake/maadeps.cmake")
include(${PROJECT_SOURCE_DIR}/MaaUtils/MaaUtils.cmake)
```

`MaaUtils.cmake` 里的 `if(NOT DEFINED MAADEPS_DIR)` 钩子保留，方便单独使用 MaaUtils 时不破坏默认行为；`MAA_DEPS_CONFIG` 未定义时会回退到 `MaaDeps/maadeps.cmake`。

## 发布 SDK

```powershell
powershell -File .\tools\package-sdk.ps1 -Version v1.0.0
```

产物 `dist/MaaCore-sdk-windows-x64-v1.0.0.zip`：

```
MaaCore-sdk-windows-x64-v1.0.0/
├── bin/
│   ├── MaaCore.dll / MaaCore.pdb
│   ├── MaaUtils.dll / MaaUtils.pdb
│   ├── opencv_world4_maa.dll
│   ├── onnxruntime_maa.dll
│   ├── onnxruntime_providers_shared_maa.dll
│   ├── fastdeploy_ppocr_maa.dll
│   └── DirectML.dll
├── include/            AsstCaller.h / AsstCallerExtra.h / AsstPort.h / MaaCore.h
├── README.md           集成说明（tools/sdk/README.md）
└── LICENSE.md
```

- 默认**不含** `onnxruntime_providers_cuda.dll`（174 MB），需要时加 `-IncludeCuda`；此时 `deps/runtime/maa-x64-windows/` 里必须先放回该文件（发布用的依赖包里没有它）。
- `resource/` 不在包内：它随游戏版本更新，应由启动器自行分发。

CI 见 `.github/workflows/maacore-release.yml`：打 `v*` tag 自动构建、打包并创建 Release；也可手动 `workflow_dispatch` 指定版本。

## 注意与边界

1. **MaaCore 仍必须依赖 5 个二进制库**：OpenCV、ONNXRuntime、fastdeploy_ppocr、Boost、zlib。本次改的是「从哪拿」，不是「不用」。
2. **没有从源码重建 ONNXRuntime / FastDeploy**：它们是 MaaDeps 的定制构建，自行编译成本极高；当前方案复用其产物，但由本仓库打包、锚定哈希、独立分发。
3. **`deps/` 不入库**：`.gitignore` 已忽略 `/deps/`、`/dist/`。首次构建必须联网下载一次依赖包。
4. **CI 缓存**：缓存键绑定 `tools/deps-manifest.json` 的内容哈希；缓存未命中时 bootstrap 会自动下载。
5. **升级上游**：`sync_upstream_core.yml` 只同步源码；若上游升级 MaaDeps 版本或 CMake 结构，需要重新裁剪一次 `deps/` 并发布新 bundle。

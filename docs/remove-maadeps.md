# 移除 MaaDeps 依赖（de-MaaDeps）

本文记录本仓库如何脱离 `MaaUtils/MaaDeps`，改用**上游官方二进制 + 官方源码**提供依赖，以及当前的发布流程。

## 结论速览

- 二进制依赖不再来自 MaaDeps，也不再应用 MaaDeps 的自定义 patch。
- `deps/` 由 `tools/build-upstream-deps.ps1` 从官方发布物组装：
  - OpenCV 4.12.0（官方 Windows 包）
  - ONNXRuntime 1.19.2 DirectML（官方 NuGet）
  - DirectML 1.15.4（官方 NuGet）
  - Boost 1.89.0（官方源码，仅编译 Regex）
  - zlib 1.3.1（官方源码，静态库）
- FastDeploy 1.0.7 是唯一没有匹配上游 Windows 预编译包的组件；沿用现有 `fastdeploy_ppocr_maa.dll`（Windows 上本身没有 MaaDeps 源码 patch）。
- `MaaUtils` 以源码形式 vendored 在仓库中，随工程编译。
- 依赖包通过 `tools/deps-manifest.json` 锚定 URL + SHA-256，由 `tools/fetch-deps.ps1` 下载。
- 当前发布包：`MaaCore-deps-windows-x64-v3.zip`（约 195 MB）。
- 实测通过：Release / Debug 构建、`AsstLoadResource` / `AsstCreate`、FastDeploy OCR 推理、ONNXRuntime 会话、Boost.Process 子进程。

## 目录与职责

```
deps/                        不入库；由 fetch-deps.ps1 或 build-upstream-deps.ps1 生成
├── include/                 OpenCV / ONNXRuntime / FastDeploy / Boost / zlib 头文件
├── lib/                     Release 导入库 / 静态库
│   ├── opencv_world4.lib       从官方 DLL 生成的导入库（指向 opencv_world4_maa.dll）
│   ├── onnxruntime.lib         从官方 DLL 生成的导入库（指向 onnxruntime_maa.dll）
│   ├── boost_regex.lib         官方源码编译
│   ├── zlib.lib                官方源码编译（静态）
│   └── cmake/                  OpenCV / Boost 的自定义 CONFIG 文件
├── bin/                     Release DLL
├── debug/                   Debug 库/DLL
├── share/                   FastDeploy 的 CMake config
└── runtime/maa-x64-windows/ 构建产物复制用运行时 DLL（含 msvc-debug/）

MaaUtils/                    入库，源码，随工程编译
cmake/
├── maadeps.cmake            CMake 适配层（triplet、maadeps_install、OpenCV/ZLIB 路径）
└── upstream/
    ├── OpenCVConfig.cmake   官方 OpenCV + _maa 命名适配
    └── BoostConfig.cmake    官方 Boost + 编译宏
tools/
├── deps-manifest.json       依赖包清单（URL + sha256 + 版本）
├── fetch-deps.ps1           下载 / 校验 / 解压依赖包
├── build-upstream-deps.ps1  从官方发布物重新组装 deps/
├── pack-deps.ps1            把 deps/ 打成可发布压缩包
├── bootstrap-standalone.ps1 构建前统一入口
└── package-sdk.ps1          打 SDK 发布包
```

## 首次构建

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\bootstrap-standalone.ps1
powershell -ExecutionPolicy Bypass -File .\tools\build-maacore-only.ps1 -SkipBootstrap -UseSccache -NoFresh
```

`fetch-deps.ps1` 的行为：

1. 读取 `tools/deps-manifest.json`，按当前平台选择 target（如 `windows-x64`）；
2. 命中 `deps/.bundle-version` 标记就直接返回；
3. 否则下载到 `.bootstrap/deps/`，校验 SHA-256 后解压到仓库根目录；
4. 解压后再校验 `include/`、`lib/`、`share/`、`runtime/maa-x64-windows/` 是否齐全。

## 从官方源码/发布物重建 deps

```powershell
# 本地已有 deps/ 时，FastDeploy 会自动从旧 deps 复制
powershell -File .\tools\build-upstream-deps.ps1

# 指定 FastDeploy 来源
powershell -File .\tools\build-upstream-deps.ps1 -FastDeployFrom C:\path\to\deps

# 强制重新下载
powershell -File .\tools\build-upstream-deps.ps1 -Force
```

脚本会：

1. 下载并校验官方 OpenCV / ORT / DirectML / Boost / zlib（带固定 SHA-256）；
2. 解压 OpenCV SFX、NuGet 包和源码包；
3. 用 CMake 编译 zlib 的 Release/Debug 静态库；
4. 用 CMake 编译 Boost.Regex 的 Release/Debug 静态库；
5. 从官方 OpenCV/ORT DLL 生成 `_maa` 命名的导入库；
6. 组装 `deps/`（含 Debug 配置）；
7. 复制 `cmake/upstream/` 下的 CMake config。

FastDeploy 没有官方 Windows 预编译包可用，脚本按以下顺序取用：

1. `-FastDeployFrom`；
2. 现有 `deps/include/fastdeploy`；
3. 下载上一个依赖包（`-FastDeployUrl`）。

## 发布依赖包

```powershell
powershell -File .\tools\pack-deps.ps1 -BundleVersion v3 -UpdateManifest
```

生成 `dist/MaaCore-deps-windows-x64-v3.zip`，上传到 tag 为 `deps-v3` 的 GitHub Release，再提交 `tools/deps-manifest.json`。

`pack-deps.ps1` 使用固定时间戳和排序后的条目写 zip，同一份输入会得到同一个 SHA-256。当前 v3 包：

- 大小：约 195 MB
- SHA-256：`c9ff316ad0cd5dadaaaee68bc4067072ef3db3d8a88e04f3800f70c8b99ffe74`
- URL：`https://github.com/ksqeib/MaaCore/releases/download/deps-v3/MaaCore-deps-windows-x64-v3.zip`

## 关于 MaaDeps 的 patch

这些 patch 已全部不再使用：

| Patch | 处理 |
|---|---|
| ORT `revert-pr-21492`（Min/Max NaN） | 不再应用，使用官方 ORT 语义 |
| ORT 的 CMake / clang / RC / PR 系列 patch | 不需要，直接使用官方二进制 |
| Boost.Asio `windows_handle_inheritance` | 不再应用 |
| Boost.Asio `windows_alloca_header` | 不再应用 |
| Boost.Asio `0001-add-options` | 用 `BOOST_ASIO_DISABLE_BOOST_DATE_TIME` / `BOOST_ASIO_DISABLE_BOOST_CONTEXT_FIBER` 替代 |
| Boost.Process `opt-filesystem` | 用 `BOOST_PROCESS_USE_STD_FS` 替代 |
| FastDeploy `float16` | Windows 无关，未应用 |
| OpenCV / zlib / DirectML | 本来就没有 MaaDeps patch |

保留了三个**适配层**（不是行为 patch）：

1. **`_maa` 命名 + 导入库**
   官方 DLL 重命名为 `opencv_world4_maa.dll` / `onnxruntime_maa.dll`，导入库由 `dumpbin` + `lib /def` 从官方 DLL 生成。这样 MaaCore 和现成的 FastDeploy DLL 共用同一个模块。
2. **Boost.Process v1 命名空间**
   Boost 1.89 单体版把 v1 API 放进 `boost::process::v1`。`MaaUtils/include/MaaUtils/IOStream/BoostIO.hpp` 用 `__has_include(<boost/process/v1.hpp>)` 兼容新旧两种布局。
3. **FastDeploy**
   当前没有匹配的上游 Windows 预编译包，暂用现有 DLL；如果需要 100% 自建，需要从 MaaXYZ/FastDeploy 源码用这套官方 OpenCV/ORT 重新编译。

## 风险与边界

1. **ORT Min/Max NaN patch 被去掉**：如果某个模型在 `Min/Max` 中遇到 NaN，结果会与旧 MaaDeps 版不同；当前 OCR/ONNX 测试未触发。
2. **Boost.Asio socket 继承 patch 被去掉**：PlayTools 的 TCP socket 不再强制 `NO_HANDLE_INHERIT`；子进程侧仍有 MaaUtils 的 `prevent_inherit`。
3. **FastDeploy 仍是现成二进制**：不是从源码现场编译，但 Windows 上它本来就没有 MaaDeps 源码 patch。
4. **Debug 依赖已包含**：官方 OpenCV debug DLL、Debug Boost.Regex、Debug zlib、旧 FastDeploy debug DLL 都已打进 deps，Debug 构建可正常链接和加载。
5. **升级依赖**：修改版本号/URL/SHA-256 后重新跑 `build-upstream-deps.ps1`，再打新的 bundle。

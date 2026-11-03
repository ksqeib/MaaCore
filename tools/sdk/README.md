# MaaCore SDK

适用于其他启动器集成的 MaaCore 独立发行包（Windows x64）。

## 主包内容

zip/7z 根目录：

```
bin/
  MaaCore.dll          MaaCore 主库（C ABI，见 include/AsstCaller.h）
  MaaUtils.dll         MaaCore 依赖的通用库
deps.json              依赖版本信息（供自动化识别）
README.md              本说明
LICENSE.md
```

**第三方 DLL 不在主包内。** 启动器需要根据 `deps.json` 自行提供：

| 文件 | 依赖 | 版本 |
|---|---|---|
| `opencv_world4_maa.dll` | OpenCV | 4.12.0 |
| `onnxruntime_maa.dll` | ONNXRuntime | 1.19.2 DirectML |
| `DirectML.dll` | DirectML | 1.15.4 |
| `fastdeploy_ppocr_maa.dll` | FastDeploy | 1.0.7 |

`deps.json` 的 `dependencies` 字段包含版本号，`runtimeFiles` 包含文件名映射，`fastdeployBundle` 包含 FastDeploy 小包的下载地址和 SHA-256。自动化程序可以对比版本号决定是否需要更新第三方 DLL。

## 符号包

同一次发布还会提供：

```
MaaCore-sdk-windows-x64-<version>-symbols.7z
  bin/MaaCore.pdb
  bin/MaaUtils.pdb
```

主包默认不包含 PDB。

## 头文件

主包默认不包含头文件。需要集成时请使用仓库内的 `include/upstream/`：

- `AsstCaller.h`
- `AsstCallerExtra.h`
- `AsstPort.h`
- `MaaCore.h`

也可以在打包时加 `-IncludeHeaders` 把公开头文件一起放进去。

## 使用方式

1. 将 `MaaCore.dll`、`MaaUtils.dll` 与第三方 DLL 放在同一目录（或加入 `PATH`）。
2. 确保第三方 DLL 版本与 `deps.json` 一致，不要混用不同版本。
3. 调用 `AsstLoadResource(path)` 指向 MAA 资源目录（`resource/`），再调用 `AsstCreate` / `AsstCreateEx`。
4. 运行时依赖 Visual C++ 运行库（与构建所用的 MSVC 版本一致）。

最小示例：

```c
#include "AsstCaller.h"

int main(void)
{
    if (!AsstLoadResource("path/to/resource-parent")) {
        return 1;
    }

    AsstHandle handle = AsstCreateEx(NULL, NULL);
    if (handle == NULL) {
        return 1;
    }

    AsstAppendTask(handle, "StartUp", NULL);
    AsstStart(handle);
    AsstStop(handle);
    AsstDestroy(handle);
    return 0;
}
```

## 版本与兼容性

- 本包由 `ksqeib/MaaCore` 的独立构建流程产出，不是 MAA 官方发布包。
- `MaaCore.dll`、`MaaUtils.dll` 与第三方 DLL 必须整体匹配；升级时请同时更新 `deps.json` 中列出的依赖。
- `AsstGetVersion()` 返回构建时的版本（发布包通常是 `v*` tag）。

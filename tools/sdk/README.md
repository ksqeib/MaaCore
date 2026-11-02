# MaaCore SDK

适用于其他启动器集成的 MaaCore 独立发行包（Windows x64）。

## 目录结构

```
bin/
  MaaCore.dll                          MaaCore 主库（C ABI，见 include/AsstCaller.h）
  MaaCore.pdb                          RelWithDebInfo 调试符号
  MaaUtils.dll                         MaaCore 依赖的通用库
  opencv_world4_maa.dll                图像处理
  onnxruntime_maa.dll                  模型推理
  onnxruntime_providers_shared_maa.dll ONNXRuntime 共享 provider
  fastdeploy_ppocr_maa.dll             PP-OCR 管线
  DirectML.dll                         DirectML GPU 推理后端
include/
  AsstCaller.h                         C 接口
  AsstCallerExtra.h                    扩展 C 接口
  AsstPort.h                           平台/回调定义
  MaaCore.h                            C++ 接口
  module.modulemap                     Swift / Clang module 定义
```

CUDA provider（`onnxruntime_providers_cuda.dll`）不包含在本包内；需要 CUDA 推理时请向发布方索取包含该文件的变体。

## 使用方式

1. 将 `bin/` 下所有 DLL 与你的启动器可执行文件放在同一目录（或加入 `PATH`）。
2. 将 `include/` 加入集成工程的头文件搜索路径。
3. 调用 `AsstLoadResource(path)` 指向 MAA 资源目录（`resource/`），再调用 `AsstCreate` / `AsstCreateEx`。
4. 运行时依赖 Visual C++ 运行库（与构建所用的 MSVC 版本一致）。

最小示例：

```c
#include "AsstCaller.h"

int main(void)
{
    if (!AsstLoadResource("path/to/resource")) {
        return 1;
    }

    AsstHandle handle = AsstCreateEx(NULL, NULL, NULL);
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
- `MaaCore.dll`、`MaaUtils.dll` 与 `bin/` 下的运行时 DLL 必须整体替换，不要混用不同版本。
- 升级时请同时更新 `include/` 头文件。

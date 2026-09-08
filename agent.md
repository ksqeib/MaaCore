# MaaCore Standalone Agent Rules

## Scope

This repository is maintained only for building:

- `MaaCore.dll`
- `MaaCore.pdb`

No GUI, packaging, or runtime functional validation is required in this repo workflow.

## Non-Goals

- Do not run parent-repository build flow.
- Do not depend on sparse checkout of parent repository.
- Do not require `resource/` for build success.

## Dependency Policy

- Keep API headers in `include/upstream/` (tracked in this repo).
- Keep required third-party headers in `include/3rd/` (tracked in this repo).
- Keep binary/toolchain deps via `MaaUtils` + `MaaDeps`.

## Build Contract

- Build target: `MaaCore`
- Configuration: `RelWithDebInfo` (default)
- Expected outputs:
  - `build-standalone/bin/RelWithDebInfo/MaaCore.dll`
  - `build-standalone/bin/RelWithDebInfo/MaaCore.pdb`


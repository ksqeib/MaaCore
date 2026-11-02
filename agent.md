# MaaCore Standalone Agent Rules

## Scope

This repository is maintained only for building:

- `MaaCore.dll`
- `MaaCore.pdb`
- an optional launcher-facing SDK zip (`tools/package-sdk.ps1`)

No GUI, packaging of `resource/`, or runtime functional validation is required in this repo workflow.

## Non-Goals

- Do not run parent-repository build flow.
- Do not depend on sparse checkout of parent repository.
- Do not require `resource/` for build success.

## Dependency Policy

- Keep API headers in `include/upstream/` (tracked in this repo).
- Keep required third-party headers in `include/3rd/` (tracked in this repo).
- Keep `MaaUtils/` source vendored and build it in-tree (no git submodule).
- Provide binary deps through `deps/`, pinned by `tools/deps-manifest.json` (URL + SHA-256) and fetched by `tools/fetch-deps.ps1`.
- Do not reintroduce `MaaUtils/MaaDeps` as a submodule or download path.

## Build Contract

- Build target: `MaaCore`
- Configuration: `RelWithDebInfo` (default)
- Expected outputs:
  - `build-standalone/bin/RelWithDebInfo/MaaCore.dll`
  - `build-standalone/bin/RelWithDebInfo/MaaCore.pdb`


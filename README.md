# mesa-loonggpu-loongarch64

Documentation and verification scaffold for the **Mesa / LoongGPU user-space
graphics stack** on AOSC OS loongarch64 (Loongson 3B6000M, LG200 GPU).

> This repo contains no driver source. It records how the stack is actually
> assembled on this machine, what was measured on 2026-11-18 (kernel
> `7.1.7-aosc-main-16k`), and how to re-check it. The LoongGPU Mesa fork is
> shipped as binary packages by the vendor; upstream Mesa does not contain a
> LoongGPU Gallium driver.

## 中文速览

- 系统装的是 Mesa 26.2.6，但 `glxinfo` 报的却是 **Mesa 24.0.5**——因为
  OpenGL/EGL/DRI 实际走的是 `loonggl` 包里的厂商分支，不是系统 Mesa。
- 调用链：`libGL/libEGL (glvnd → loonggpu)` → `loonggpu_dri.so` → `libldrm`
  → `/dev/dri/renderD128` → DKMS 内核模块 `loonggpu` → LG200。
- 实测 OpenGL 3.3 硬件加速可用（glxgears 约 62 FPS，受 60Hz 刷新率限制）；
  EGL 1.5；但 OpenCL 只有软件 `rusticl`、Vulkan 只有软件 `llvmpipe`。
- 内核 `loonggpu` 是外树 DKMS 模块，会 taint 内核；这就是之前 7.1.13
  `drm_stub_open` 崩溃里 `loonggpu(OE)` 的来源。

## Why this exists

The package names are misleading: `mesa` is 26.2.6, yet the renderer reports
Mesa 24.0.5. That is because AOSC ships two separate user-space stacks:

| Component | Upstream `mesa` (26.2.6) | Vendor `loonggl` (1.0.2+lnd25.1-3) |
|---|---|---|
| GLX/EGL | `libGLX_mesa.so`, `libEGL_mesa.so` (via glvnd alternatives) | `libGLX_loonggpu.so`, `libEGL_loonggpu.so`, `libloonggpu_glapi.so` |
| DRI driver | `/usr/lib/dri-mesa/swrast_dri.so` etc. (mostly symlinks to `libdril_dri.so`) | `/usr/lib/loonggpu/dri/loonggpu_dri.so`, symlinked at `/usr/lib/dri/loonggpu_dri.so` |
| GBM | `libgbm.so.1` | `loonggpu_gbm.so` |
| OpenGL version | — | **3.3 core/compat, GLES 3.0, Mesa 24.0.5** |
| OpenCL | `rusticl` 3.1 (software) | `loong-gpucomp` installed but no ICD registered |
| Vulkan | lavapipe / llvmpipe (software) | none |

`libGL.so.1` / `libEGL.so.1` are glvnd dispatchers (`update-alternatives` points
at `/usr/lib/glvnd/`); the actual driver is selected at runtime, and here it
resolves to the LoongGPU one.

## Call chain

```
glxinfo / glxgears / mpv / Chromium
        │  libGL.so.1 / libEGL.so.1 (glvnd)
        ▼
/usr/lib/loonggpu/libGLX_loonggpu.so  +  libEGL_loonggpu.so
        │  DRI
        ▼
/usr/lib/dri/loonggpu_dri.so → /usr/lib/loonggpu/dri/loonggpu_dri.so
        │  libloonggpu_glapi.so, libldrm.so.1, libdrm.so.2
        ▼
/dev/dri/renderD128  (mode 666)
        │  DRM ioctl
        ▼
kernel loonggpu (DKMS, out-of-tree, taints kernel)
        │
        ▼
LG200 GPU  (PCI 00:06.0, 0014:7a35)
```

## Measured status (2026-11-18)

| Check | Result |
|---|---|
| `glxinfo -B` | direct rendering **yes**; renderer `LoongGPU(TM) LG200 (DRM 1.0.0 / 7.1.7-aosc-main-16k, LGC)`; OpenGL **3.3** core & compat, GLES 3.0; **Mesa 24.0.5**; accelerated yes |
| `glxgears` (5 s) | 309 frames / 5 s = **61.8 FPS**, vsync-locked to the 60 Hz panel — not a throughput benchmark |
| `eglinfo -B` | EGL 1.5, vendor `Mesa Project`, client APIs OpenGL + OpenGL_ES |
| `clinfo` | only `rusticl` (Mesa/X.org, OpenCL 3.1, software); no LoongGPU device |
| `vulkaninfo --summary` | `llvmpipe` (LLVM 22.1.8) — software only |
| Kernel module | `loonggpu` loaded (out-of-tree, `(OE)`), VRAM 1024M, GART 256M, GTT 3072M |
| `/dev/dri` | `renderD128` 666; `card0`/`card1` 660 (video group) |

Raw command output and interpretation are in
[`docs/STACK_AND_VERIFICATION.md`](docs/STACK_AND_VERIFICATION.md).

## Verify

Read-only, no sudo, no system changes:

```sh
bash scripts/check-render.sh
```

Or manually:

```sh
glxinfo -B | grep -E 'renderer string|version string|Accelerated'
eglinfo -B | grep 'EGL version string'
timeout 8 glxgears
clinfo | grep -E 'Platform Name|Device Name'
vulkaninfo --summary | grep -E 'deviceName|driverName'
```

## Build notes

- The LoongGPU DRI driver is **binary-only** here (from `loonggl`); there is no
  source tree in this repo. Do not expect a rebuild of AOSC `mesa` to produce
  `loonggpu_dri.so` — upstream Mesa 26.2.6 has no LoongGPU Gallium driver.
- Upstream `mesa` can still be rebuilt with the local no-root AOSC toolchain
  (`~/packaging/aosc-abbs/build.sh`, ACBS/autobuild4). That path is for Mesa
  itself (libGL/libEGL/libgbm/Rusticl/lavapipe), not for the vendor DRI blob.
- Upstream direction: chenhuacai commit `15aa0c4` (`drm/loongson: Add the new
  loongson-gpu driver`) adds an in-tree DRM driver for LG200-era hardware.
  A matching upstream Mesa Gallium driver is not present in Mesa 26.2.6.

## Known limitations

- OpenGL is capped at 3.3 (no GL 4.x) with this vendor fork.
- `glxinfo` reports "Video memory: 1MB" although the kernel reserves 1024M VRAM
  and 256M GART — that field is not trustworthy on this driver.
- OpenCL/Vulkan paths are software-only; `loong-gpucomp` has no ICD in
  `/etc/OpenCL/vendors/`, so `clinfo` cannot see the GPU compute runtime.
- The kernel `loonggpu` module is out-of-tree and taints the kernel; the
  7.1.13 `drm_stub_open` Oops involved this module.
- `glxgears` FPS is vsync-limited; use it only to confirm acceleration, not
  to compare performance.

## References

- AOSC GPU driver announcement: https://aosc.io/news/2026-03-09-gpu-driver-changes
- AOSC LoongGPU/VPU preview: https://aosc.io/news/2025-12-31-loonggpu-and-loongvpu-preview
- Mesa: https://www.mesa3d.org/
- New in-tree Loongson DRM driver: https://github.com/chenhuacai/linux/commit/15aa0c4338d14a623796de21732f6d5455d051e2

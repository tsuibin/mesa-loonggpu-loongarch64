# Stack layout and verification results

Everything below was measured on 2026-11-18 on the author's machine:
Loongson 3B6000M (loongarch64), LG200 GPU at PCI `00:06.0` (`0014:7a35`),
AOSC OS, kernel `7.1.7-aosc-main-16k`, X11 `DISPLAY=:0`.

## 1. Why `mesa` 26.2.6 reports Mesa 24.0.5

`dpkg -l mesa` says `1:26.2.6`, but `glxinfo -B` reports Mesa 24.0.5. The
reason is package layering:

```sh
$ update-alternatives --query libGL.so.1 | grep -E 'Best|Value'
Best: /usr/lib/glvnd/libGL.so.1
Value: /usr/lib/glvnd/libGL.so.1
$ update-alternatives --query libEGL.so.1 | grep -E 'Best|Value'
Best: /usr/lib/glvnd/libEGL.so.1
Value: /usr/lib/glvnd/libEGL.so.1
```

glvnd dispatches to the vendor loader:

```sh
$ ls -l /usr/lib/dri/loonggpu_dri.so
lrwxrwxrwx ... /usr/lib/dri/loonggpu_dri.so -> ../loonggpu/dri/loonggpu_dri.so
$ ls -l /usr/lib/loonggpu/
libEGL_loonggpu.so.0.0.0
libGLX_loonggpu.so.0.0.0
libloonggpu_glapi.so.0.0.0
loonggpu_gbm.so
dri/loonggpu_dri.so
$ dpkg -L loonggl | grep -E 'libEGL|libGLX|glapi|gbm|dri'
/usr/lib/loonggpu/...
```

`ldd /usr/lib/loonggpu/dri/loonggpu_dri.so` links against
`libloonggpu_glapi.so.0`, `libldrm.so.1`, `libdrm.so.2`, `libzstd.so.1` —
firmly the vendor stack, not upstream `libGLX_mesa.so`.

## 2. Kernel side

```sh
$ lsmod | grep -E '^loonggpu'
loonggpu   2588672  42
$ modinfo loonggpu | grep -E 'filename|description'
filename:    /lib/modules/7.1.7-aosc-main-16k/updates/dkms/loonggpu.ko.zst
description: Loongson LGxx GPU Driver
$ dmesg | grep -i loonggpu
[drm] loonggpu kernel modesetting enabled.
[drm] initializing kernel modesetting (LG200 0x0014:0x7A35 ...)
[drm] Set 2K3000 device in loonggpu driver
loonggpu 0000:00:06.0: Video RAM: 1024M ...
loonggpu 0000:00:06.0: GART: 256M ...
[drm] loonggpu: 3072M of GTT memory ready.
$ ls -l /dev/dri/
crw-rw----+ 1 root video  226,   0 card0
crw-rw----+ 1 root video  226,   1 card1
crw-rw-rw-  1 root render 226, 128 renderD128
```

The module comes from the `loonggpu-kernel-dkms` package under
`updates/dkms/`, so it is marked `(OE)` and taints the kernel.

## 3. OpenGL (`glxinfo`, `glxgears`)

```sh
$ glxinfo -B
name of display: :0
display: :0  screen: 0
direct rendering: Yes
Extended renderer info (GLX_MESA_query_renderer):
    Vendor: X.Org (0xe)
    Device: LoongGPU(TM) LG200 (DRM 1.0.0 / 7.1.7-aosc-main-16k, LGC) (0x7a35)
    Version: 24.0.5
    Accelerated: yes
    Video memory: 1MB
    Unified memory: no
    Preferred profile: core (0x1)
    Max core profile version: 3.3
    Max compat profile version: 3.3
    Max GLES1 profile version: 1.1
    Max GLES[23] profile version: 3.0
OpenGL core profile version string: 3.3 (Core Profile) Mesa 24.0.5
OpenGL version string: 3.3 (Compatibility Profile) Mesa 24.0.5
OpenGL ES profile version string: OpenGL ES 3.0 Mesa 24.0.5
```

`Accelerated: yes` is the important line — this is not llvmpipe.

```sh
$ timeout 8 glxgears
Running synchronized to the vertical refresh.  The framerate should be
approximately the same as the monitor refresh rate.
309 frames in 5.0 seconds = 61.776 FPS
```

Interpretation: vsync locks the number to the 60 Hz panel, so this only proves
hardware rendering is active. It is not a benchmark.

## 4. EGL

```sh
$ eglinfo -B | grep -E 'EGL (API|vendor|version|client)'
EGL API version: 1.5
EGL vendor string: Mesa Project
EGL version string: 1.5
EGL client APIs: OpenGL OpenGL_ES
```

## 5. OpenCL

```sh
$ clinfo | grep -E 'Platform Name|Device Name|Platform Version'
Platform Name                    rusticl
Platform Vendor                  Mesa/X.org
Platform Version                 OpenCL 3.1
```

Only `rusticl` (software) is registered. Although `loong-gpucomp` is installed
(`/usr/lib/libloong-gpucomp.so.1`), `/etc/OpenCL/vendors/` contains only
`rusticl.icd`, so the GPU compute runtime is invisible to ICD loaders.

## 6. Vulkan

```sh
$ vulkaninfo --summary | grep -E 'deviceName|driverName|apiVersion'
apiVersion  = 1.4.354
deviceName  = llvmpipe (LLVM 22.1.8, 128 bits)
driverName  = llvmpipe
```

Software rendering only; there is no LoongGPU Vulkan driver in this stack.

## 7. Package inventory

| Package | Version | Role |
|---|---|---|
| `mesa` | 1:26.2.6 | upstream runtime (libGLX/EGL_mesa, libgbm, Rusticl, lavapipe) |
| `loonggl` | 2:1.0.2+lnd25.1-3 | vendor GL/EGL/GBM + `loonggpu_dri.so` (Mesa 24.0.5 fork) |
| `ldrm` | 2:1.0.2+lnd25.1 | DRM interface library for LoongGPU |
| `loong-gpucomp` | 2:1.0.2+lnd25.1 | GPU compute library, no registered OpenCL ICD |
| `loonggpu-driver` | 2:1.0.2+lnd25.1 | meta package pulling all of the above |
| `loonggpu-kernel-dkms` | 2:1.0.2+lnd25.1-1 | out-of-tree kernel DRM module |
| `loonggpu-settings` | 1:1.0.2+ud25.1~rc1.10 | `/etc/loonggpu/loonggpu_driver.conf` |
| `firmware-loongson-graphics` | 2:1.0.2+lnd25.1 | GPU firmware |
| `xserver-xorg-video-loonggpu` | 2:1.0.2+lnd25.1-1 | X.Org DDX driver |
| `mesa-demos` | 9.0.0-1 | glxinfo, glxgears |

## 8. Re-check after an upgrade

Kernel package upgrades rebuild the DKMS module and can change the ABI that
`loonggpu_dri.so` speaks. After any `oma upgrade` touching `mesa`,
`loonggl` or the kernel:

1. `bash scripts/check-render.sh` — all GL/EGL checks should still report
   accelerated rendering.
2. If `glxinfo -B` suddenly reports `llvmpipe` or `softpipe`, check that
   `/usr/lib/dri/loonggpu_dri.so` still exists and that the `loonggpu`
   kernel module loaded (`dmesg | grep -i loonggpu`).
3. Do not use Vulkan/OpenCL results to judge the GL stack; they are separate
   software paths here.

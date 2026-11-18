#!/usr/bin/env bash
#
# check-render.sh - read-only LoongGPU / Mesa stack verification.
#
# No sudo, no package changes, no config writes. Prints what is actually
# loaded and which renderer the GL/EGL/OpenCL/Vulkan paths resolve to.

set -u
cd "$(dirname "$0")/.." || exit 1

info() { printf '  [info] %s\n' "$*"; }
ok()   { printf '  [OK]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; }
head1() { printf '\n== %s ==\n' "$*"; }

head1 "1. Kernel and device"
uname -r | sed 's/^/  kernel: /'
if lsmod | grep -qE '^loonggpu[[:space:]]'; then
    ok "loonggpu module loaded"
else
    bad "loonggpu module not loaded"
fi
if [ -e /dev/dri/renderD128 ]; then
    ls -l /dev/dri/renderD128 | sed 's/^/  /'
else
    bad "/dev/dri/renderD128 missing"
fi
dmesg 2>/dev/null | grep -i 'loonggpu.*modesetting' | tail -1 | sed 's/^/  /' || true

head1 "2. DRI driver and GL libraries"
ls -l /usr/lib/dri/loonggpu_dri.so 2>&1 | sed 's/^/  /'
for f in /usr/lib/loonggpu/libGLX_loonggpu.so.0.0.0 \
         /usr/lib/loonggpu/libEGL_loonggpu.so.0.0.0; do
    [ -f "$f" ] && ok "$(basename "$f")" || bad "$(basename "$f") missing"
done

head1 "3. OpenGL"
if command -v glxinfo >/dev/null 2>&1; then
    GLX=$(glxinfo -B 2>&1)
    echo "$GLX" | grep -E 'direct rendering|Device:|Version:|Accelerated:|OpenGL renderer string|OpenGL core profile version string' | sed 's/^/  /'
    echo "$GLX" | grep -q 'Accelerated: yes' && ok "OpenGL hardware accelerated" || bad "OpenGL not accelerated"
else
    info "glxinfo not installed (mesa-demos)"
fi

head1 "4. EGL"
if command -v eglinfo >/dev/null 2>&1; then
    eglinfo -B 2>/dev/null | grep -m3 -E 'EGL (API version|vendor string|version string|client APIs)' | sed 's/^/  /'
else
    info "eglinfo not installed"
fi

head1 "5. glxgears (5 s, vsync-limited)"
if command -v glxgears >/dev/null 2>&1; then
    timeout 8 glxgears 2>&1 | grep -m1 'frames in' | sed 's/^/  /' || info "glxgears produced no frame count"
else
    info "glxgears not installed (mesa-demos)"
fi

head1 "6. OpenCL"
if command -v clinfo >/dev/null 2>&1; then
    clinfo 2>/dev/null | grep -m2 -E 'Platform Name|Device Name' | sed 's/^/  /'
    [ -f /etc/OpenCL/vendors/rusticl.icd ] && info "rusticl ICD present (software)" || true
else
    info "clinfo not installed"
fi

head1 "7. Vulkan"
if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary 2>/dev/null | grep -m2 -E 'deviceName|driverName' | sed 's/^/  /'
else
    info "vulkaninfo not installed"
fi

printf '\nDone. See docs/STACK_AND_VERIFICATION.md for reference output.\n'

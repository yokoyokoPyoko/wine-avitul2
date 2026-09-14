#!/bin/bash
# Deploy patched AviUtl2 DLLs/EXEs built from $WINE_SOURCE to the
# wine-staging installation and the default prefix.
#
# 64-bit builtin DLLs/EXEs must exist in BOTH locations:
#   /opt/wine-staging/lib/wine/x86_64-windows/  (builtin lookup)
#   ~/.wine/drive_c/windows/system32/           (KnownDLLs resolution)
# If only one side is updated, `err:module:import_dll ... not found` occurs.
#
# IMPORTANT: always run AviUtl2 with the staging binary by full path:
#   /opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe
# (`wine` on PATH is the distro's Wine 10.0 and must NOT be used.)
#
# Order of operations after a wine-staging upgrade:
#   1. /opt/wine-staging/bin/wineboot -u   (refresh prefix with stock DLLs)
#   2. sudo ./deploy_dlls.sh               (overwrite with patched DLLs)
# Prefix update rewrites system32, so deploying BEFORE it would be lost.
set -euo pipefail

WINE_SOURCE="${WINE_SOURCE:-/home/p-yoko/Program/Cpp/Wine_Aviutl2_Adapter/wine}"
WINE_BIN="/opt/wine-staging/bin/wine"
OPT_DIR="/opt/wine-staging/lib/wine/x86_64-windows"
PREFIX_DIR="$HOME/.wine/drive_c/windows/system32"

# Patched modules (dxgi needs no patch, so it is intentionally not deployed)
DLLS="wined3d d3d11 comdlg32 shell32 dwrite"
DLL_DIRS="wined3d d3d11 comdlg32 shell32 dwrite"

[ -x "$WINE_BIN" ] || { echo "ERROR: $WINE_BIN not found" >&2; exit 1; }
[ -d "$WINE_SOURCE" ] || { echo "ERROR: $WINE_SOURCE not found" >&2; exit 1; }
[ -d "$PREFIX_DIR" ] || { echo "ERROR: prefix dir $PREFIX_DIR not found" >&2; exit 1; }

# Set SKIP_OPT=1 to update only the prefix (system32 + helpers), e.g. when
# sudo is unavailable. /opt copies must then be done separately.
SKIP_OPT="${SKIP_OPT:-0}"

opt_cp() {
    if [ "$SKIP_OPT" = 1 ]; then return 0; fi
    sudo cp "$@"
}

opt_backup_once() {
    if [ "$SKIP_OPT" = 1 ]; then return 0; fi
    backup_once "$1" sudo
}
backup_once() {
    local dest="$1" use_sudo="$2"
    local ver
    ver="$("$WINE_BIN" --version 2>/dev/null | tr -c '[:alnum:].' '_' || echo unknown)"
    if [ "$use_sudo" = sudo ]; then
        sudo sh -c "ls '${dest}'.stock-* >/dev/null 2>&1 || cp '$dest' '${dest}.stock-${ver}'"
    else
        ls "${dest}".stock-* >/dev/null 2>&1 || cp "$dest" "${dest}.stock-${ver}"
    fi
}

install_dll() {
    local name="$1" srcdir="$2"
    local src="$WINE_SOURCE/dlls/$srcdir/x86_64-windows/$name.dll"
    [ -f "$src" ] || { echo "ERROR: built $src not found. Build it first." >&2; exit 1; }
    opt_backup_once "$OPT_DIR/$name.dll"
    opt_cp "$src" "$OPT_DIR/"
    backup_once "$PREFIX_DIR/$name.dll" nosudo
    cp "$src" "$PREFIX_DIR/"
    echo "deployed $name.dll"
}

for pair in "wined3d:wined3d" "d3d11:d3d11" "comdlg32:comdlg32" "shell32:shell32" "dwrite:dwrite"; do
    install_dll "${pair%%:*}" "${pair##*:}"
done

# explorer.exe (patched: /select -> native file manager)
EXPLORER_SRC="$WINE_SOURCE/programs/explorer/x86_64-windows/explorer.exe"
if [ -f "$EXPLORER_SRC" ]; then
    opt_backup_once "$OPT_DIR/explorer.exe"
    opt_cp "$EXPLORER_SRC" "$OPT_DIR/"
    backup_once "$PREFIX_DIR/explorer.exe" nosudo
    cp "$EXPLORER_SRC" "$PREFIX_DIR/"
    echo "deployed explorer.exe"
else
    echo "WARNING: $EXPLORER_SRC not found, skipping explorer.exe" >&2
fi

# Build and deploy winelib helpers (native file dialog / native file manager)
TMPD="$(mktemp -d /tmp/winehelpers.XXXXXX)"
trap 'rm -rf "$TMPD"' EXIT
for prog in winefiledialog wineopenfolder; do
    SRC="$WINE_SOURCE/programs/$prog/main.c"
    [ -f "$SRC" ] || { echo "ERROR: $SRC not found" >&2; exit 1; }
    /opt/wine-staging/bin/winegcc -municode -I"$WINE_SOURCE/include" \
        -c "$SRC" -o "$TMPD/$prog.o"
    /opt/wine-staging/bin/winegcc -municode -o "$TMPD/$prog.exe" "$TMPD/$prog.o"
    backup_once "$PREFIX_DIR/$prog.exe" nosudo
    cp "$TMPD/$prog.exe.so" "$PREFIX_DIR/$prog.exe"
    echo "deployed $prog.exe"
done

echo "Done! Installed from: $("$WINE_BIN" --version)"

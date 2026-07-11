#!/bin/bash
WINE_SOURCE="/home/p-yoko/Wine_Aviutl2_Adapter/wine"
OPT_DIR="/opt/wine-staging/lib/wine/x86_64-windows"
PREFIX_DIR="$HOME/.wine/drive_c/windows/system32"

sudo cp "$WINE_SOURCE/dlls/wined3d/x86_64-windows/wined3d.dll" "$OPT_DIR/"
sudo cp "$WINE_SOURCE/dlls/d3d11/x86_64-windows/d3d11.dll" "$OPT_DIR/"
sudo cp "$WINE_SOURCE/dlls/comdlg32/x86_64-windows/comdlg32.dll" "$OPT_DIR/"
sudo cp "$WINE_SOURCE/dlls/shell32/x86_64-windows/shell32.dll" "$OPT_DIR/"
sudo cp "$WINE_SOURCE/dlls/dwrite/x86_64-windows/dwrite.dll" "$OPT_DIR/"

# Also copy to system32 for KnownDLLs resolution (64-bit)
cp "$WINE_SOURCE/dlls/comdlg32/x86_64-windows/comdlg32.dll" "$PREFIX_DIR/"
cp "$WINE_SOURCE/dlls/shell32/x86_64-windows/shell32.dll" "$PREFIX_DIR/"
cp "$WINE_SOURCE/dlls/dwrite/x86_64-windows/dwrite.dll" "$PREFIX_DIR/"

# Build and deploy winefiledialog.exe (winelib helper for native file dialog)
WINE_SOURCE_DIR="/home/p-yoko/Wine_Aviutl2_Adapter/wine"
/opt/wine-staging/bin/winegcc -municode -I"$WINE_SOURCE_DIR/include" \
  -c "$WINE_SOURCE_DIR/programs/winefiledialog/main.c" -o /home/p-yoko/tmp_winefiledialog.o
/opt/wine-staging/bin/winegcc -municode -o /home/p-yoko/tmp_winefiledialog.exe /home/p-yoko/tmp_winefiledialog.o
cp /home/p-yoko/tmp_winefiledialog.exe.so ~/.wine/drive_c/windows/system32/winefiledialog.exe
rm -f /home/p-yoko/tmp_winefiledialog*

# Build and deploy wineopenfolder.exe (winelib helper for native file manager / xdg-open)
/opt/wine-staging/bin/winegcc -municode -I"$WINE_SOURCE_DIR/include" \
  -c "$WINE_SOURCE_DIR/programs/wineopenfolder/main.c" -o /home/p-yoko/tmp_wineopenfolder.o
/opt/wine-staging/bin/winegcc -municode -o /home/p-yoko/tmp_wineopenfolder.exe /home/p-yoko/tmp_wineopenfolder.o
cp /home/p-yoko/tmp_wineopenfolder.exe.so ~/.wine/drive_c/windows/system32/wineopenfolder.exe
rm -f /home/p-yoko/tmp_wineopenfolder*

echo "Done!"

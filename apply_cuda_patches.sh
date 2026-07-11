#!/bin/bash
set -e
PATCH_DIR="/home/p-yoko/Wine_Aviutl2_Adapter/wine-staging/patches"
WINE_DIR="/home/p-yoko/Wine_Aviutl2_Adapter/wine"

cd "$WINE_DIR"

echo "Applying nvcuda patches..."
for patch in "$PATCH_DIR"/nvcuda-CUDA_Support/*.patch; do
    if [[ "$(basename "$patch")" == "0001"* ]]; then
        # manual patch for 0001 was done/attempted, let's just try applying
        echo "Applying $patch"
        git apply --reject --whitespace=fix "$patch" || true
    else
        echo "Applying $patch"
        git apply --reject --whitespace=fix "$patch" || true
    fi
done

echo "Applying nvcuvid patches..."
for patch in "$PATCH_DIR"/nvcuvid-CUDA_Video_Support/*.patch; do
    echo "Applying $patch"
    git apply --reject --whitespace=fix "$patch" || true
done

echo "Applying nvencodeapi patches..."
for patch in "$PATCH_DIR"/nvencodeapi-Video_Encoder/*.patch; do
    echo "Applying $patch"
    git apply --reject --whitespace=fix "$patch" || true
done

echo "Done applying patches."

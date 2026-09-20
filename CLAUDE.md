# Wine AviUtl2 Adapter 開発ガイド

AviUtl2 を Wine 上で動作させるための wined3d/d3d11 の修正プロジェクト。

## 環境
- GPU: AMD Radeon 840M (radeonsi, RDNA3.5)
- Mesa: 25.2.8
- wine-staging: 11.16 (`/opt/wine-staging`, 2026-09 更新)
- ソースコード: `wine/` は旧 11.7 ベースで温存。新規の正は 11.16 worktree (`wine-11.16/`、
  プロジェクト直下の永続配置。ブランチ `aviutl2-wine-11.16`。コミット自体は `wine/.git` に保存されるため
  worktree 消失時も `git worktree` で復旧可)。`aviutl2_*.patch` は staging-11.16 適用済みツリーにクリーン適用確認済み。
  (2026-09-20 追記: `/tmp/opencode` 配置は tmp クリーンで消失したためプロジェクト直下に移設。`/tmp` は一時ファイルのみに使うこと)

## 注意: `/usr/bin/wine` は別物 (2026-09-14)
- `PATH` 上の `wine`/`winecfg` はディストロ標準の **Wine 10.0**。`winecfg` で見える `10.0` はこれ。
- AviUtl2 の起動・`wineboot`・`winecfg` は必ずフルパス `/opt/wine-staging/bin/wine*` を使用すること。
  10.0 の `winecfg` が `~/.wine` prefix をダウングレードした実績あり（`wineboot -u` で復旧）。

## 注意: ソースツリーの状態 (2026-06-06)

- **`wine/`**: 全パッチ適用済み（G8R8_G8B8, MAILBOX, oldSwapchain, per-swapchain context, 各バグ修正, ファイルダイアログ改良, 最小化クラッシュ修正, dwrite. 各種修正, ネイティブファイルマネージャ統合, 内蔵エクスプローラー拡張, ネットワークFS対応, .lnk改善, GTKブックマーク同期改善）。`adapter_vk.c` の閉じ括弧欠落バグは修正済み。
- **注意**: `dlls/shell32/shfldr_mycomp.c` に Linux の `/proc/mounts` をパースしてマウントドライブを My Computer 内に追加するコードを含む。`_ILCreateUnixMountPIDL` で作成する PIDL の `cb` 値は正しく計算すること（`sizeof(SHITEMID)` は abID[0] を含むため +1 不要）。`ISF_MyComputer_fnBindToObject` は PT_UNIXMOUNT PIDL の後続要素にも対応（子フォルダ移動可能）。ネットワークFS (cifs/nfs/smbfs) は `_access()` チェックをスキップし、バインド前に `/proc/mounts` でマウント存在確認を行う。

**結論**: `wine/` が唯一の正しいソース。

## ビルド・デプロイ手順 (11.16)
- **ソース準備**: `wine-11.16/` (worktree, ブランチ `aviutl2-wine-11.16`)
  = `wine-11.16` タグ + wine-staging v11.16 (`staging/patchinstall.py --all --backend=git-apply`,
  最後の `autoreconf` は未インストールのため失敗するがパッチ適用自体は完了する) + `aviutl2_*.patch`
- **configure**: `./configure --enable-win64` (11.7 ツリーの `config.status --config` と同条件)
- **ビルド** (各モジュール):
  ```
  make -j$(nproc) dlls/wined3d/x86_64-windows/wined3d.dll dlls/d3d11/x86_64-windows/d3d11.dll \
    dlls/comdlg32/x86_64-windows/comdlg32.dll dlls/shell32/x86_64-windows/shell32.dll \
    dlls/dwrite/x86_64-windows/dwrite.dll programs/explorer/x86_64-windows/explorer.exe
  ```
- **prefix 更新→デプロイ** (順序厳守。prefix 更新が system32 を素に戻すため):
  ```
  /opt/wine-staging/bin/wineboot -u
  cd ~/Program/Cpp/Wine_Aviutl2_Adapter && sudo ./deploy_dlls.sh
  ```
  (`deploy_dlls.sh` は `WINE_SOURCE` 環境変数でソース切替可、`SKIP_OPT=1` で prefix のみ更新可。
  `/opt` と `~/.wine/.../system32` の両方に配置する。`dxgi` はパッチ対象外のためデプロイしない)
- **旧 11.7 ツリーの手順** (`wine/` ディレクトリ): 以下は参考記録。新規ビルドは 11.16 worktree で行うこと。
- **wined3d のビルド** (旧):
  ```
  cd ~/Wine_Aviutl2_Adapter/wine
  make -j$(nproc) dlls/wined3d/x86_64-windows/wined3d.dll
  ```
- **d3d11 のビルド**: `cd wine/dlls/d3d11 && make -j$(nproc)`
- **dxgi のビルド**: `cd wine/dlls/dxgi && make -j$(nproc)`
- **dwrite のビルド**: `cd wine/dlls/dwrite && make -j$(nproc)`
- **comdlg32 のビルド**: `cd wine/dlls/comdlg32 && make -j$(nproc)`
- **shell32 のビルド**: `cd wine && make -j$(nproc) dlls/shell32/x86_64-windows/shell32.dll`
- **explorer のビルド**: `cd wine && make -j$(nproc) programs/explorer/x86_64-windows/explorer.exe`
- **DLL のデプロイ**: `cd ~/Wine_Aviutl2_Adapter && sudo ./deploy_dlls.sh`
  (デプロイスクリプトは winefiledialog をソースから自動ビルドし、wined3d/d3d11/comdlg32/shell32 を `/opt/wine-staging/` および `~/.wine/system32/` にコピーする)

  **注意**: 64bit DLL/EXE (`x86_64-windows/`) は `/opt/wine-staging/lib/wine/x86_64-windows/` (builtin) と
  `~/.wine/drive_c/windows/system32/` (KnownDLLs 解決用) の **両方** に配置する必要がある。
  片方だけだと `err:module:import_dll ... not found` エラーになる。

## バックアップ
- `/opt/wine-staging/.../*.patched` = 元の wine-staging 純正 DLL（未パッチ）
- リストア: `cp ...dll.patched ...dll`

## デバッグコマンド
- **通常実行**:
  `/opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe`
- **詳細ログ付き実行**:
  `WINEDEBUG=+d3d11,+d3d /opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe 2>&1 | tee /tmp/debug.log`
- **shell/explorer デバッグ**:
  `WINEDEBUG=+shell,+explorer /opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe 2>&1 | tee /tmp/debug.log`

## 解決済みの課題: 動画表示の緑がかり

### 実際の原因
`dlls/wined3d/utils.c` の `convert_g8r8_g8b8_unorm` 関数が G8R8_G8B8 (packed YUV 4:2:2) フォーマットを GL_RG8（2チャンネル）に変換する際に、Cr（Vクロマ）チャンネルを完全に捨てていた。マクロピクセル `[Y0, Cb, Y1, Cr]` の Cr が消失し、シェーダーが「Cr=0」で YUV→RGB 変換を行うと緑成分（G）が過剰にブーストされることで緑がかりが発生していた。

※CLAUDE.md の古い記述では NV12 フォーマットマッピングが原因とされていたが、AviUtl2 は実際には NV12 テクスチャを作成していないことが判明。NV12 関連の修正は不要。

### 修正内容
1. **`dlls/wined3d/utils.c`**: `convert_g8r8_g8b8_unorm` の出力先を GL_RG8(2ch) → GL_RGBA8(4ch) に変更。`[R=Cb, G=Y, B=Cr, A=255]` ですべての YUV 成分を保持するようにした。

2. **`dlls/d3d11/view.c`**: SRV フォーマット強制マッチパッチを削除し、リトライ方式に変更。フォーマット不一致時に一度失敗 → リソースフォーマットで再試行する。
   - 古い強制マッチ（常にリソースフォーマットに合わせる）→ GUI が暗転
   - リトライ方式（最初は要求フォーマット、失敗したらリソースフォーマット）→ GUI 正常

3. **`dlls/d3d11/texture.c`**: G8R8_G8B8_UNORM を YUV フォーマットフラグストリッピング対象に追加。Vulkan など非対応バックエンドでも B8G8R8A8 フォールバックできるようにした。

## 解決済みの課題: d3d11.dll での NULL ポインタアクセス (Page Fault)
`dlls/d3d11/device.c` の `CreateRenderTargetView` 等で、アプリケーションが `view` 引数に NULL を渡した場合にクラッシュする。

### 修正内容
各ビュー作成関数 (`CreateShaderResourceView`, `CreateRenderTargetView` 等) の冒頭で `view` 引数の NULL チェックを追加し、NULL の場合は `E_INVALIDARG` を返すようにした。`gradienteditor.aux2` プラグインが該当。

## Vulkan バックエンドの動画カラー対応 (2026-05-17)

### 追加修正（OpenGL の修正だけでは不十分だった部分）
Vulkan バックエンドで G8R8_G8B8_UNORM を正しく扱うために以下を追加:

1. **`dlls/wined3d/utils.c`**: `vulkan_formats[]` テーブルに G8R8_G8B8_UNORM → VK_FORMAT_R8G8B8A8_UNORM マッピングを追加
2. **`dlls/wined3d/utils.c`**: `init_vulkan_format_info` 内で G8R8_G8B8_UNORM の `format->upload = convert_g8r8_g8b8_unorm`, `conv_byte_count = 4` を設定
3. **`dlls/wined3d/texture_vk.c`**: Vulkan テクスチャアップロードパスに `format->upload` 呼び出しを追加。`conv_byte_count` でステージングバッファピッチを計算

### 現在のステータス
- 動画の緑がかり: ✅ 解決（Vulkan/OpenGL 両方）
- 動画の色が正しく表示される: ✅ `wine/` からの正しい DLL で解決
- 画面が真っ黒 / 表示異常: ✅ 解決（Vulkan/OpenGL 両方）
- UI 黒いチラつき / 部分更新バグ: ✅ 解決（Vulkan/OpenGL 両方）

## 解決済み: 画面が真っ黒およびUIチラつき・部分更新バグの解消 (2026-05-17)

### 状況と解決内容
1. **画面が真っ黒・アサーション失敗**:
   - Vulkanバックエンドにおいて、スワップチェーン再作成時に古い `VkSwapchainKHR` を `oldSwapchain` に正しく引き継ぎ、新しいスワップチェーンとイメージ、セマフォが**完全に成功した後**にのみ古いリソースを安全にクリーンアップするロジックを再設計・実装しました。
   - `vk_surface` (Vulkanサーフェス) が既に有効な場合は破棄せずに再利用することで、リサイズ時のアサーション失敗（黒画面化）を解決しました。
   - 退避させた `vk_semaphores` (無名構造体配列) の安全な破棄のため、一時的にポインタを戻して解放する型安全な仕組みを導入してコンパイルエラーを回避しました。

2. **UIが更新されたところだけ表示され、他が真っ黒になるバグ**:
   - **真の解決策**: バッファローテーション自体は正常に実行させつつ、`wined3d_swapchain_vk_blit` 内のイメージバリアにおいて、スワップ効果が `DISCARD` の際にもイメージレイアウトが `VK_IMAGE_LAYOUT_UNDEFINED` にクリアされるのを防ぎ、常に内容を維持する **`VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL`** を使用するように修正しました。

3. **低遅延プレゼンモード (MAILBOX) の適用**:
   - `swap_interval == 0`（VSync オフ）の際、`VK_PRESENT_MODE_MAILBOX_KHR` を最優先で選択して画面のティアリングとチラつきを劇的に改善しました。

## パッチファイル一覧

| パッチファイル | 対象ファイル | パッチ内容 | 状態 |
|---------------|-------------|-----------|:----:|
| `aviutl2_wined3d.patch` | `dlls/wined3d/utils.c` | G8R8_G8B8 コンバーター, Vulkan フォーマットテーブル, upload/conv_byte_count | ✅ |
| `aviutl2_wined3d.patch` | `dlls/wined3d/swapchain.c` | MAILBOX, oldSwapchain, per-swapchain context, IMMEDIATE優先, 最小化クラッシュ修正 | ✅ |
| `aviutl2_wined3d.patch` | `dlls/wined3d/texture_vk.c` | Vulkan upload パスで format->upload 呼び出し | ✅ |
| `aviutl2_wined3d.patch` | `dlls/wined3d/view.c` | Vulkan SRV フォーマットリトライ | ✅ |
| `aviutl2_wined3d.patch` | `dlls/wined3d/cs.c` | Present フレームレイテンシスロットルバイパス, スピンループポンプ | ✅ |
| `aviutl2_wined3d.patch` | `dlls/wined3d/wined3d_private.h` | `wined3d_resource_wait_idle` にポンプ | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/d3d11/device.c` | NULL view チェック, SwapDeviceContextState 高速パス | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/d3d11/texture.c` | G8R8_G8B8 YUV フラグストリッピング | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/d3d11/view.c` | SRV フォーマットリトライ | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/comdlg32/filedlg.c` | GetOpenFileNameW→native dialog 分岐 | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/comdlg32/itemdlg.c` | IFileOpenDialog→native dialog 分岐 | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/dwrite/layout.c` | HitTestPoint/TextPosition/TextRange 実装 | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `programs/winefiledialog/main.c` | zenity ラッパー | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/shell32/*.c` | shell32 各種修正 | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `dlls/ole32/ole2.c` | D&D クラッシュ修正 | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `programs/explorer/explorer.c` | /select → native file manager | ✅ |
| `aviutl2_d3d11_dwrite.patch` | `programs/wineopenfolder/main.c` | wineopenfolder.exe | ✅ |
| `aviutl2_user32.patch` | `dlls/user32/message.c` | PeekMessageW VK_SPACE dispatch 介入（再生中には到達せず無効） | ❌ 無効確認済み |

## 解決済み: Vulkan バックエンドの「1フレーム遅れ」問題 (2026-05-18)

### 修正内容
| ファイル | 変更 |
|---------|------|
| `dlls/wined3d/swapchain.c` | `VK_PRESENT_MODE_IMMEDIATE_KHR` を MAILBOX より優先、`srcAccessMask` に `VK_ACCESS_TRANSFER_WRITE_BIT` を追加 |

## 組み込みファイルダイアログの改良 (2026-05-18)

### AviUtl2 で使用される API
AviUtl2 は `IFileOpenDialog` ではなく **`GetOpenFileNameW`** (Win95 スタイル) を使用する。

### 使用方法（デフォルトで有効）
```bash
/opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe
WINE_NATIVE_FILE_DIALOG=0 /opt/wine-staging/bin/wine /home/p-yoko/App/Aviutl2/aviutl2.exe  # 無効化
```

## 解決済み: 最小化時のクラッシュ (2026-05-18)

| ファイル | 変更 |
|---------|------|
| `dlls/wined3d/swapchain.c` | `GetClientRect()` 後、`width`/`height` を `max(1, ...)` で下限保証 |

## 解決済み: dwrite の各種バグ修正 (2026-05-20)
- `HitTestPoint` E_NOTIMPL クラッシュ → フル実装
- 空行でのキャレット位置・選択範囲（HitTestTextRange）修正

## 解決済み: 場所を開く・フォルダ移動を Nautilus/xdg-open にリダイレクト (2026-05-20)

```
アプリ → 場所を開く
  ├─ SHOpenFolderAndSelectItems → shell32.dll → wineopenfolder.exe
  ├─ ShellExecuteExW(explorer.exe, /select) → shell32.dll → wineopenfolder.exe
  └─ CreateProcess(explorer.exe, /select) → 修正済み explorer.exe
```

## 修正履歴

### 1. マウントドライブの子フォルダが開けない（2026-05-26 ✅ 解決）
`shfldr_mycomp.c` `ISF_MyComputer_fnBindToObject` に PIDL チェーン後続要素の処理を追加。

### 2. Favorites の .lnk ブックマーク（2026-06-02 ✅ 解決）
`BrowseToIDList` 内遅延解決 + `ICommDlgBrowser3_fnOnDefaultCommand` での右ペーン .lnk 解決。

### 3. My Computer がネットワーク共有マウントでフリーズ（2026-06-02 ✅ 解決）
`is_network_fs()` 追加 → `_access()` チェックをスキップ。

### 4. GTK ブックマーク同期で削除したブックマークが残る（2026-06-02 ✅ 解決）
`sync_gtk_bookmarks_to_favorites()` に Phase 2（古い `.lnk` 削除）を追加。

## 解決済み: GCMZDrops/MyAssetManager ドラッグ＆ドロップ時のクラッシュ (2026-06-06)

| ファイル | 変更 |
|---------|------|
| `dlls/shell32/dataobject.c` | `pidl_count && pidls` が成り立たない場合フォーマット事前生成スキップ |
| `dlls/shell32/clipboard.c` | `RenderFILENAMEA`/`W` に NULL pidl ガード |
| `dlls/ole32/ole2.c` | `DestroyWindow` 後 `DefWindowProcW` 防止、NULL dropSource ガード |
| `dlls/shell32/ebrowser.c` | `IShellBrowser_fnSendControlMsg` ポインタ上書きバグ修正 |

## コーディング規約
- **言語**: C (Wine coding style)
- **ログ**: `TRACE`, `FIXME`, `ERR` を適切に使用する。[v12.7-STAGING] ログは `WARN` レベル（デフォルト非表示）。
- **型**: `WINED3DFMT_*`, `DXGI_FORMAT_*` などの列挙型に注意。

## 未解決: 動画再生中の Space キー停止不能 (2026-07-05 調査継続中)

### 症状
AviUtl2 で動画再生中に Space キー（またはマウスクリック）で停止できない。非再生中は Space・ボタン共に正常動作する。「再生中の操作が一気に実行される」現象あり。

### 確定した根本原因（2026-07-23）
動画再生中 AviUtl2 のメインスレッドは **`PeekMessageW` を全く呼ばない**（GetTickCount ログで確認済み）。メッセージはキューに溜まり続け、再生終了後の通常ループで一括取得される。

### 試行済みのアプローチ（すべて失敗または不安定）

#### user32.dll レベル（message.c）
| アプローチ | 結果 |
|-----------|------|
| `dispatch_message` 内で VK_SPACE → ボタンクリック変換 | Space が dispatch されない（再生中 DispatchMessageW 未呼出） |
| `PeekMessageW` 内で VK_SPACE intercept + `BM_CLICK` 送信 | aviutl2Manager の子孫に Button クラスの再生/停止ボタン不在（カスタム描画） |
| `PeekMessageW` 内で `dispatch_message` 直接呼出 | wined3d mutex 再入によるデッドロック |
| `GetMessageW` 内で VK_SPACE 消費 + mouse click 合成 | X BadWindow クラッシュ（座標が誤ったウィンドウを指す） |
| `IsDialogMessageW` / `DefDlgProcW` に VK_SPACE ハンドラ | AviUtl2 が呼んでいない／aviutl2Manager はダイアログではない |
| `PeekMessageW` 内で VK_SPACE dispatch + WM_NULL（2026-07-10） | AviUtl2 が再生中 PeekMessageW を**呼ばず**無効確定 |
| `PeekMessageW` 内で GetTickCount() ログ確認（2026-07-10） | 再生中の呼出なし・再生終了後に一括到着を確定 |

#### wined3d.dll レベル（cs.c スピンループ）
| アプローチ | 結果 |
|-----------|------|
| `wined3d_cs_queue_require_space` / `wined3d_resource_wait_idle` / `wined3d_cs_mt_finish` にポンプ追加 | クラッシュなし・起動安定。ただし再生中にスピンループへ到達しないため停止不能のまま |

### 対応不要の修正
| ファイル | 変更 | 状態 |
|---------|------|:--:|
| `dlls/user32/dialog.c` | IsDialogMessageW VK_SPACE ハンドラ | ⚠️ revert 記録と矛盾・コードはツリーに残存 (2026-09-14 確認)。無害だが未整理 |
| `dlls/user32/defdlg.c` | DefDlgProcW VK_SPACE ハンドラ | ⚠️ 同上 |
| `dlls/user32/message.c` | PeekMessageW 改造 | ✅ ツリーから除去済み。`aviutl2_user32.patch` からも除外 |

### 現在適用中の修正
| ファイル | 変更 | 状態 |
|---------|------|:--:|
| `dlls/wined3d/swapchain.c` | `wined3d_mutex_unlock` 後に再入ガード付き 1メッセージポンプ | ⚠️ 効果未確認・安定 |
| `dlls/wined3d/cs.c` | Present フレームレイテンシスロットルバイパス (`while(0){}`) | ✅ 安定 |
| `dlls/d3d11/device.c` | SwapDeviceContextState 高速パス、NULL view チェック、ERR→WARN | ✅ 安定 |

### 新しいアプローチの根拠（2026-07-05）
- cs.c スピンループへのポンプは「CSキューが満杯・drain 待ち時のみ到達」→ 再生中ほぼ到達しない
- `wined3d_swapchain_present` は **毎フレーム必ず呼ばれ**、mutex unlock 後はメインスレッド・mutex フリーの安全な状態
- AviUtl2 再生ループが PeekMessage を呼ばないなら、メッセージはキューに残る → ここでのポンプが有効なはず

### d3d_perf トレース結果（2026-07-05 判明）

```
0128: wined3d_cs_mt_finish "Waiting for queue 0 to be empty" → すぐ "Queue is now empty"（繰り返し）
016c: wined3d_cs_queue_require_space "Waiting for free space"（大量に連続）
```

**スレッド構成が判明:**
- `0128` = AviUtl2 メインスレッド: `wined3d_cs_mt_finish` でフレームごとにキュー drain を待つ（短時間で解除）
- `016c` = AviUtl2 再生スレッド: D3D コマンドを大量投入し、CSキューが満杯でスピン

**重要**: Space キーは `0128`（メインスレッド）のキューに積まれる。
`0128` の `wined3d_cs_mt_finish` スピン中にポンプすれば取れるが、D3D コールスタック上なので `DispatchMessageW` が WndProc → D3D Present の再入を起こしクラッシュ。

### ❌ クラッシュ：swapchain_present 後の while ポンプ（2026-07-05）
`wined3d_swapchain_present` の mutex unlock 直後で `while(PeekMessageW + DispatchMessageW)` → AviUtl2 WndProc が Space を受けて停止処理 → 再度 D3D Present → 再入でクラッシュ。その後 revert。

### 🔄 再実装：再入ガード付き swapchain_present ポンプ（2026-07-23）
`static BOOL in_pump` ガードを追加。再入時はスキップされるためクラッシュしない設計。`while` → `if` に変更し1メッセージのみ処理。cs.c の無効ポンプは除去。

### ❌ 無効確認済み：PeekMessageW 改造（2026-07-10）
`PeekMessageW` 内: PM_REMOVE で VK_SPACE WM_KEYDOWN 取得時、`PostMessageW(msg.hwnd, ...)` で再投入し `msg_out->message = WM_NULL` に置換。
その後 `DispatchMessageW` に変更し、GetTickCount() ログで確認した結果:
- **AviUtl2 は再生中に PeekMessageW を一切呼ばない**
- メッセージは再生終了後に一括到着
- user32 レベルの介入は根本的に無効

### ❌ 過去の試行（再掲）
| アプローチ | 結果 |
|-----------|------|
| WH_GETMESSAGE フック | page fault クラッシュ（全メッセージに発動） |
| wined3d mutex unlock 直後 DispatchMessageW | 再入クラッシュ |
| wined3d_cs_mt_finish PostMessageW | 効果未確認 |
| PeekMessageW dispatch_message 直接呼出 | wined3d mutex 再入によるデッドロック |

**教訓**: D3D コールスタック上の `DispatchMessageW` は再入問題が必ず起きる。

### 現在の診断（2026-07-05 確定）
`wined3d_cs_mt_finish` の全呼び出し元を特定：

| スレッド | 関数 | タイミング |
|---------|------|-----------|
| `0124` main | `wined3d_swapchain_resize_buffers` | リサイズ時のみ |
| `01e0` decode | `wined3d_device_context_emit_map` / `emit_unmap` | 毎フレーム（ビデオデコード） |
| `0168` | 終了処理（`wined3d_swapchain_decref` 等） | 終了時のみ |

**重要**: メインスレッドは再生中に `wined3d_cs_mt_finish` でブロックされていない。d3d_perf の "Waiting for queue" は `01e0`（デコードスレッド）のものだった。

**問題の真因**: AviUtl2 の再生ループ（メインスレッド）が `PeekMessage(PM_REMOVE)` でメッセージを取り出すが dispatch しない。これは wined3d のブロックとは無関係で AviUtl2 の意図的な設計。

### 確定した事実（2026-07-10）
`PeekMessageW` 内に GetTickCount() ログを仕込んで再生中に Space を押したテストにより確定:
- **AviUtl2 は再生中に `PeekMessageW` を全く呼ばない**
- メッセージは再生終了後にキューから一括取得される（ドバッと出る）
- `DispatchMessageW` で WndProc に直接 VK_SPACE を送っても、AviUtl2 は再生中はそれを無視する
- user32.dll レベルの介入は再生中に到達しないため根本的に無効

**現在のアプローチ（2026-07-23）**: `wined3d_swapchain_present` の mutex unlock 後に再入ガード付きで DispatchMessageW。毎フレーム到達し、mutex 解放済み。再入ガード (`static BOOL in_pump`) により Present の再帰呼び出しを安全にスキップ。

### ✅ 解決（部分的）: 停止操作でのフリーズ解消・停止不可は残存 (2026-09-14)
再生中の停止操作で「応答がありません」→待機でも復帰しないデッドロックを調査・対処。

**確定したメカニズム** (診断ログ + winedbg スタックトレースで証明):
- Space (WM_KEYDOWN) をポンプが dispatch → 返ってこない (19 回中 1 回のみ未復帰＝Space)
- メインスレッドのスタック: `wined3d_swapchain_present` (D2D EndDraw 経由) → `DispatchMessageW`
  → プラグインサブクラス連鎖 (gcmzdrops/al2_ui_dressing/al2_slimming/updatechecker/discordrpc)
  → AviUtl2 本体 → **`WaitForSingleObject` で無限待ち**
- すなわちトグルハンドラは提示ループの進行を待ち、提示ループはネストした Dispatch にブロックされる
  **自己デッドロック**。D3D スタック内の dispatch では原理的に回避不可（drain 先行でも解消せず確認済み）。
  CS スレッド・デコード・描画スレッドは無関係（停止時も継続または正常終了）。

**対処**: ポンプは `WM_MOUSEMOVE` のみ中継（30 回以上の正常復帰を確認済み）。
キー・ボタン等のアクション系メッセージはキューに残し、再生終了後に実行される（ポンプ導入前の挙動）。
`wined3d_resource_wait_idle` 内の無制限 dispatch（同種の危険・発火実績なし）は除去。
再生中の停止は引き続き不可（アプリが自ループで入力処理しない設計のため Wine 側からは安全な dispatch 文脈を作れない）。
停止操作でフリーズしなくなったことのみ検証済み（2026-09-14 自己再現: idle+Space で生存確認）。

### ⏱️ 停止遅延の調査 (2026-09-15/20: 停止は効くが1〜29秒遅延)
フリーズ解消後も「Space→停止まで1〜29秒 (変動)」が残存。以下を確定済み:
- トグル自体は F_main 経由で正常 dispatch・即時復帰する。停止しないのは配送問題ではない
- デコード停止とプレゼント停止の順序・間隔は回ごとに変動 (winedbg・d3d_perf・vulkan トレースで確認)
- 原因候補の筆頭はパイプライン遅延: アプリが毎秒数千の present を発行し 99% が NOT_READY 破棄
  (空転)。キュー遅延が秒単位に膨らむと停止 ACK が間に合わない
- 対処: フレームレイテンシスロットルを有界化 (100ms タイムアウト付き待機＋ドロップ分不返却)。
  無限待機は起動時デッドロックを起こすため絶対に使わないこと (2026-09-15 に黒画面ハングで確認・revert 済み)。
  有界化後は即時停止が観測される回あり (ただし変動は残存)。再生中の重さ増加なし
- 未解決の変動要因: クリップ境界・GOP 位相・デコード先行バッファの深さのいずれか。排出完了で停止する
  ため「Space 1回＋待機」が正しい使い方。再押下はトグルで再生再開するため逆効果

### ✅ 解決: 停止遅延の安定化 (2026-09-20: 0〜2秒で安定)
最終状態で位置・再生時間によらず 0〜2 秒で停止することを確認。ただし完全な即時性には至らず。
残る分散 ( press により即時〜数秒) はアプリ内部のトグル状態機械に依存し、Wine 側からは
メッセージ配送・pacing では解消できないことが確定した (以下に証拠列挙)。現状で凍結する。
- F_main 経由の dispatch は正常・即時復帰するが、トグル実行後に映像が継続する回がある
- デコード停止とプレゼント停止の順序・間隔は回ごとに変動。単発 Space でデコードが 76ms で止まる回も、
  22 秒無視される回もある (同一バイナリ・同一操作)。トグル内部の状態競合とみられる
- present 空転 (毎秒数千回・99% 破棄) は有界スロットルで pacing (100ms 待機＋ドロップ不返却)。
  停止遅延への寄与は限定的だったが CPU 浪費の解消として維持する
- 無限待機版の黒画面ハングは起こさないこと・再生中の重さ増加なし・フリーズなしを確認済み

## 11.16 への移植 (2026-09-14 ✅ 起動確認済み)

`/opt/wine-staging` が 11.16 に更新され、配備済み DLL が素に戻ったため全パッチを移植・再ビルド。
起動確認: `timeout 45 /opt/wine-staging/bin/wine .../aviutl2.exe` で 45 秒間安定動作、
Vulkan レンダラーで UI 描画 (d2d) まで到達。import エラー・page fault なし。

### 11.7→11.16 の上流変化に伴う手動ポート (パッチファイルに反映済み)
| ファイル | 内容 |
|---------|------|
| `dlls/wined3d/decoder.c` | `&device_vk->context_vk` → `device_vk->context_vk` (上流で関数分割 `create_layered_image` へ移動) |
| `dlls/wined3d/swapchain.c` | 旧 `pending_presents` スロットルが `frame_latency_semaphore` 方式に置換 → `if (0 && ...)` でバイパス |
| `dlls/win32u/vulkan.c` | SUBOPTIMAL 抑制を `AcquireNextImage2`/`QueuePresent` に移植 (32bit client/host 分離後の新コードに対応。旧ツリー同様、非-2 系は対象外) |
| `dlls/wined3d/utils.c` | `plane_formats` が構造体ポインタ配列化 → `get_format_internal()` 代入に修正 (ビルドエラー対応) |

### 移植時のミスと対策
- パッチ再生成時に `git add -N` を `git reset` で消したまま再生成 → 新規ファイル
  (`winefiledialog/` `wineopenfolder/`) がパッチから脱落。`--check` は通るため気づきにくい。
  **対策**: 再生成後は `grep "^+++ "` で新規ファイルの存在を必ず目視確認する。
- `deploy_dlls.sh` を `WINE_SOURCE` 未指定で実行 → 旧 11.7 DLL を誤デプロイ。
  **対策**: md5 で `/opt` とビルド物の一致を必ず確認する (手順に明記)。
- `sudo` が container 制限 (NoNewPrivs) で一時不通 → `SKIP_OPT=1` で prefix 側のみ先行デプロイ。
  後に制限解消を確認しフルデプロイした。




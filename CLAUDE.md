# Wine AviUtl2 Adapter 開発ガイド

AviUtl2 を Wine 上で動作させるための wined3d/d3d11 の修正プロジェクト。

## 環境
- GPU: AMD Radeon 840M (radeonsi, RDNA3.5)
- Mesa: 25.2.8
- wine-staging: 11.8
- ソースコード: パッチ適用済みは `wine/` (wine 11.7 ベース)

## 注意: ソースツリーの状態 (2026-06-06)

- **`wine/`**: 全パッチ適用済み（G8R8_G8B8, MAILBOX, oldSwapchain, per-swapchain context, 各バグ修正, ファイルダイアログ改良, 最小化クラッシュ修正, dwrite. 各種修正, ネイティブファイルマネージャ統合, 内蔵エクスプローラー拡張, ネットワークFS対応, .lnk改善, GTKブックマーク同期改善）。`adapter_vk.c` の閉じ括弧欠落バグは修正済み。
- **注意**: `dlls/shell32/shfldr_mycomp.c` に Linux の `/proc/mounts` をパースしてマウントドライブを My Computer 内に追加するコードを含む。`_ILCreateUnixMountPIDL` で作成する PIDL の `cb` 値は正しく計算すること（`sizeof(SHITEMID)` は abID[0] を含むため +1 不要）。`ISF_MyComputer_fnBindToObject` は PT_UNIXMOUNT PIDL の後続要素にも対応（子フォルダ移動可能）。ネットワークFS (cifs/nfs/smbfs) は `_access()` チェックをスキップし、バインド前に `/proc/mounts` でマウント存在確認を行う。

**結論**: `wine/` が唯一の正しいソース。

## ビルド・デプロイ手順
- **wined3d のビルド**:
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

### 判明している根本原因
トレースにより、動画再生中 AviUtl2 のメインスレッドが `PeekMessageW(PM_REMOVE)` でメッセージをキューから取得するが **`DispatchMessageW` を呼ばない** ことが判明。再生終了後に溜まったメッセージが一括 dispatch される。

「再生中の操作が一気に実行される」挙動から、再生ループ中は PeekMessage を呼ばずメッセージがキューに溜まり続け、再生終了後の通常ループで一括処理されると推測。

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
| `dlls/user32/dialog.c` | IsDialogMessageW VK_SPACE ハンドラ | ❌ revert 済み |
| `dlls/user32/defdlg.c` | DefDlgProcW VK_SPACE ハンドラ | ❌ revert 済み |

### 現在適用中の修正
| ファイル | 変更 | 状態 |
|---------|------|:--:|
| `dlls/wined3d/cs.c` | `wined3d_cs_queue_require_space` スピンに 1メッセージ入力ポンプ | ⚠️ 効果未確認・安定 |
| `dlls/wined3d/cs.c` | `wined3d_cs_mt_finish` に 1メッセージ入力ポンプ | ⚠️ 効果未確認・安定 |
| `dlls/wined3d/wined3d_private.h` | `wined3d_resource_wait_idle` に 1メッセージ入力ポンプ | ⚠️ 効果未確認・安定 |
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

### 試行済み：swapchain_present 後のポンプ（2026-07-05 ❌ クラッシュ）
`wined3d_swapchain_present` の mutex unlock 直後で `while(PeekMessageW + DispatchMessageW)` → AviUtl2 WndProc が Space を受けて停止処理 → 再度 D3D Present 呼び出し → `wined3d_swapchain_present` 再入でクラッシュ。

### ❌ revert 済み：swapchain_present ポンプ（2026-07-05）
wined3d_cs_mt_finish の DispatchMessageW を PostMessageW に変更 → revert 済み。swapchain.c のポンプも revert 済み。

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

**残るアプローチ**: wined3d の毎フレーム到達箇所（`wined3d_swapchain_present` 等）からの介入。ただし D3D コールスタック上での `DispatchMessageW` は再入クラッシュが避けられない。

### 今後の調査方針
1. **user32 PeekMessageW 改造**: AviUtl2 が `PeekMessage(PM_REMOVE)` で VK_SPACE を取り出す際、dispatch して WM_NULL で返す（wined3d 不要、user32.dll レベルで対応）
2. **AviUtl2 の WH_KEYBOARD_LL 確認**: AviUtl2 が自身で低レベルキーフックを登録しているか確認。Wine の WH_KEYBOARD_LL 実装が不完全な可能性
3. **xdotool 外部クリック**: X11 レベルでボタンクリックを送信




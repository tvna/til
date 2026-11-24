# macOS で Chrome の自動アップデートが失敗する原因と対処

Chrome が更新されない原因が `~/Library/LaunchAgents` の所有者 (`root`) だった事例の記録。更新の失敗は Chrome の画面には出ず、更新プログラム (GoogleUpdater) のログにだけ残る。

- 環境: macOS 26.3 (Apple Silicon)。Chrome は `/Applications` にユーザー所有でインストール
- 結果: 所有者を直して Chrome を再起動すると、153.0.8010.53 → 158.0.8127.89 に更新された (2026-11-25)

## 1. 症状

- Chrome のバージョンが上がらない
- 更新プログラムが `UpdaterMain (--install) returned 27` で毎回終了する (ログ 2 ファイル分の 171 回中、成功 0 回)
- `launchctl list` に `com.google.GoogleUpdater.wake` が無い

## 2. 原因

Chrome は起動のたびに `GoogleUpdater --install` を実行し、毎時の更新ジョブ `~/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist` を作ろうとする。

`~/Library/LaunchAgents` が `root:staff` 所有 (`drwxr-xr-x`) だと一般ユーザーは書き込めず、ジョブを作れない。ジョブが無いので更新プログラムが常駐せず、更新が一度も走らない。

ログに残るエラー:

```text
Couldn't set file permissions for: ~/Library/LaunchAgents
Failed to write file://.../LaunchAgents/com.google.GoogleUpdater.wake.plist
  ... NSPOSIXErrorDomain Code=13 "Permission denied"
Failed to connect to remote mojo service ... scope: User, no updater exists.
UpdaterMain (--install) returned 27.
```

## 3. 切り分け

### 3.1 ログで終了コードを見る

```bash
L="$HOME/Library/Application Support/Google/GoogleUpdater"
grep -E "UpdaterMain \(--install\) returned|Failed to write file|Couldn't set file permissions" "$L/updater.log" | tail
```

`returned 0` なら正常。`returned 27` と `Failed to write file ... Permission denied` が並ぶなら本件。ログは `updater.log` と、ローテート済みの `updater.log.old` にある。

### 3.2 所有者と書き込みを確かめる

```bash
ls -ld ~/Library/LaunchAgents                                               # 所有者が自分でなければ異常
probe=$(mktemp "$HOME/Library/LaunchAgents/.wtest.XXXXXX") && rm "$probe"   # Permission denied なら書けない
find ~/Library -maxdepth 1 -user root                                       # ~/Library 直下の root 所有物
```

今回は、`~/Library` 直下で root 所有だったのは `LaunchAgents` だけだった。

### 3.3 ジョブの登録を確かめる

```bash
launchctl list | grep -i GoogleUpdater
ls -l ~/Library/LaunchAgents
```

修復前は、どちらも空だった。

## 4. 修復と検証

```bash
sudo chown "$USER":staff ~/Library/LaunchAgents
```

`staff` は macOS の一般ユーザーの既定グループ。

更新プログラムは Chrome の起動時に動くので、Chrome を完全に終了 (`Cmd+Q`) して起動し直す。再起動するまで結果は変わらない。次を確認する。

- ログが `UpdaterMain (--install) returned 0` になる
- `~/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist` ができ、`launchctl list` に `com.google.GoogleUpdater.wake` が出る (毎時 = `StartInterval 3600` で実行)
- 更新が走り、`/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/` に新しいバージョンのディレクトリができる (今回は約 273 MB をダウンロード)
- Chrome を再起動すると、新しいバージョンで動く

## 5. 原因ではなかったもの

誤検知しやすい点。どれも修復では直接触っておらず、修復後に更新が成功したので、原因ではないと判断した。

| 疑ったもの | 結果 |
| --- | --- |
| ディスク空き | 231 GiB 空き。問題なし |
| MDM・プロキシ | 未登録・設定なし |
| ネットワーク | `update.googleapis.com` への POST は成功 (応答 `status: ok`) |
| 空の Keystone plist (`com.google.keystone.*.plist`、181 バイト、中身は `<dict/>`) | 異常ではない。修復後に更新プログラム自身が、同じ 181 バイトの空 plist を `~/Library/LaunchAgents` に作った |
| システム領域の古い更新プログラム (v132) | ログは 2025-02-27 で止まり、ジョブも未ロード。代替の経路としては機能していないが、原因でもない |

## 事実と推測の区別

2026-11-25 時点。1 台の環境のみで確認した。

**事実 (ログ・ファイルで確認)**

- `~/Library/LaunchAgents` は `root:staff` 所有で、`touch` が `Permission denied` になった (修復前の更新日時は 2024-04-23)
- ログに `Failed to write file ... com.google.GoogleUpdater.wake.plist ... Permission denied` が出ており、`--install` は 171 回すべて終了コード 27、成功は 0 回だった
- 所有者を `staff` グループの自分に変えて Chrome を再起動すると、`--install` が `returned 0` になり、`wake.plist` の作成とジョブ登録、新バージョンへの更新、新バージョンでの起動まで通った
- 更新プログラムは `scope: User` (ユーザー領域) で動いていた

**推測 (未検証)**

- `LaunchAgents` が root 所有になった経緯。root 権限で動いた何らかのツールが作った可能性があるが、原因は特定していない
- 空の Keystone plist を更新プログラムが作るのは、旧 Keystone を無効化する Google の移行処理とみられる。動作は確認したが、意図は公式資料で確認していない
- Chrome を管理者権限でシステム全体にインストールした環境の更新経路は、調べていない
- macOS 26.3 以外のバージョンや Intel Mac での挙動は、確認していない
- Google / Chromium の公式資料は参照していない。ログのメッセージとファイルの状態だけから結論を出した

## 参考 (調べた場所)

- `~/Library/Application Support/Google/GoogleUpdater/updater.log`、`updater.log.old`、`updater_history.jsonl` (ユーザー領域の更新プログラムのログと履歴)
- `~/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist` (毎時の更新ジョブ)
- `/Library/Application Support/Google/GoogleUpdater/` (システム領域の更新プログラム)

# Kali Linux on VirtualBox (Windows) — Vagrant 構築手順

Windows 上の VirtualBox に、Kali 公式の Vagrant ボックス `kalilinux/rolling` から Kali Linux の VM を作成する。

- VM 定義: **Vagrant**（`Vagrantfile`）
- ハイパーバイザ: **VirtualBox**
- ゲスト初期設定: **shell provisioner**（`provision/bootstrap.sh`：タイムゾーン、キーマップ、任意で upgrade と追加パッケージ）

```
 Windows (ホスト)                                   VM: Kali Linux (kalilinux/rolling)
┌───────────────────────────┐                     ┌──────────────────────────────┐
│ PowerShell                │                     │ provision/bootstrap.sh       │
│  vagrant up / ssh / halt  │── VirtualBox API ──▶│ ユーザー vagrant (sudo 可)    │
│ VirtualBox 7.2            │── ssh 127.0.0.1:2222▶│ /vagrant ← このディレクトリ   │
└───────────────────────────┘                     └──────────────────────────────┘
```

---

## 1. 前提（一次情報で確認した事実）

2026-10-16 時点で確認。

| 項目 | 内容 | 出典 |
|---|---|---|
| ボックス | `kalilinux/rolling` の最新版は `2026.2.0`（2026-06-30 公開）。プロバイダは hyperv / virtualbox / libvirt / vmware_desktop、すべて amd64 | Vagrant Cloud API `https://app.vagrantup.com/api/v2/box/kalilinux/rolling` |
| ボックスのユーザー | ユーザー名は `vagrant`、SSH 鍵は Vagrant 標準の insecure keypair（初回起動時に Vagrant が新しい鍵に差し替える）、sudo 可、資格情報は `vagrant` で統一 | [Kali Blog: Kali Vagrant Rebuilt](https://www.kali.org/blog/kali-vagrant-rebuilt/) |
| ボックスの作り方 | Packer から kali-vm ビルドスクリプト（Linux 上で全 VM を同じ手順で生成）に移行済み | 同上 |
| ディスク使用量 | ダウンロード後に起動すると約 10GB を使う | [Kali Docs: Kali inside Vagrant](https://www.kali.org/docs/virtualization/install-vagrant-guest-vm/) |
| Vagrant の版 | 最新は 2.4.9。VirtualBox 7.2 への対応は 2.4.9 から | [Vagrant CHANGELOG](https://github.com/hashicorp/vagrant/blob/main/CHANGELOG.md) / HashiCorp checkpoint API |
| VirtualBox の版 | 最新の安定版は 7.2.20 | `https://download.virtualbox.org/virtualbox/LATEST-STABLE.TXT` |
| 共有フォルダ | VirtualBox の共有フォルダでは `SharedFoldersEnableSymlinksCreate` が既定で有効。信頼できないゲストでは無効化が推奨されている | Vagrant の起動メッセージ（上記 Kali Blog のデモ出力に記載） |

**推測（未検証）:**

- Windows で Hyper-V（WSL2、仮想化ベースのセキュリティなど）が有効だと、VirtualBox が遅くなったり起動に失敗したりすることがある。その場合は「5. トラブルシュート」を参照。
- ボックスにはデスクトップ環境が入っている前提で `KALI_GUI=true` を既定にしている（旧 Kali の発表では GUI 有効が既定）。最新ボックスでの確認はしていない。

---

## 2. ディレクトリ構成

```
kali-vagrant/
├── README.md               # この手順書
├── Vagrantfile             # VM 定義（設定値は環境変数で上書き）
├── provision/
│   └── bootstrap.sh        # ゲスト初期設定
├── .gitattributes          # Windows で clone しても *.sh を LF のままにする
└── .gitignore              # .vagrant/ を除外
```

---

## 3. 手順（Windows / PowerShell）

### 3.1 ツールのインストール（初回のみ）

```powershell
# パッケージ ID はインストール前に winget search で確認する
winget search Vagrant
winget search VirtualBox
winget install --id Hashicorp.Vagrant -e
winget install --id Oracle.VirtualBox -e
```

インストール後に PowerShell を開き直してから、版を確認する。

```powershell
vagrant --version        # 2.4.9 以上
VBoxManage --version     # 7.2.x（PATH に無ければ "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"）
```

> **注意（推測）:** `Hashicorp.Vagrant` / `Oracle.VirtualBox` という winget のパッケージ ID は今回は確認していない。見つからない場合は公式サイトからインストーラーを入手する。

### 3.2 VM の作成

```powershell
git clone https://github.com/tvna/til.git
cd til\kali-vagrant
vagrant up --provider virtualbox
```

初回はボックス（数 GB）のダウンロードがあるので時間がかかる。

### 3.3 接続

```powershell
vagrant ssh               # CLI で入る
```

GUI はコンソールウィンドウに表示される（`KALI_GUI=true` の場合）。ログインは `vagrant` / `vagrant`。

### 3.4 日常の操作

| やりたいこと | コマンド |
|---|---|
| 停止 | `vagrant halt` |
| 再起動（Vagrantfile の変更を反映） | `vagrant reload` |
| プロビジョニングだけ再実行 | `vagrant provision` |
| スナップショット取得・復元 | `vagrant snapshot save clean` / `vagrant snapshot restore clean` |
| 状態確認 | `vagrant status` |
| 破棄（VM を削除） | `vagrant destroy -f` |
| ボックスを更新 | `KALI_BOX_VERSION` を新しい版にしてから `vagrant destroy -f; vagrant up` |

---

## 4. 設定値（環境変数）

PowerShell で `$env:変数名 = "値"` を設定してから `vagrant up` を実行する。

| 変数 | 既定値 | 内容 |
|---|---|---|
| `KALI_BOX_VERSION` | `2026.2.0` | ボックスの版を固定する（再現性のため） |
| `KALI_VM_NAME` | `kali-vagrant` | VirtualBox 上の VM 名とホスト名 |
| `KALI_CPUS` | `2` | vCPU 数 |
| `KALI_MEMORY` | `4096` | メモリ（MB） |
| `KALI_GUI` | `true` | VirtualBox のコンソールウィンドウを表示するか |
| `KALI_PRIVATE_IP` | （空） | ホストオンリーの IP（例: `192.168.56.10`）。空なら NAT のみ |
| `KALI_UPGRADE` | `false` | `true` なら初回に `apt full-upgrade` を実行 |
| `KALI_PACKAGES` | （空） | 追加パッケージ（例: `kali-linux-default seclists`） |
| `KALI_TIMEZONE` | `Asia/Tokyo` | タイムゾーン |
| `KALI_KEYMAP` | `jp` | キーボード配列 |

例:

```powershell
$env:KALI_MEMORY   = "8192"
$env:KALI_CPUS     = "4"
$env:KALI_UPGRADE  = "true"
$env:KALI_PACKAGES = "kali-linux-default"
vagrant up --provider virtualbox
```

> 環境変数は `vagrant up` のたびに読み込まれる。`KALI_UPGRADE` / `KALI_PACKAGES` / `KALI_TIMEZONE` / `KALI_KEYMAP` は、プロビジョニングが走るとき（初回の `vagrant up` と `vagrant provision`）にだけ反映される。

---

## 5. トラブルシュート

| 症状 | 対処 |
|---|---|
| `vagrant up` で VT-x / AMD-V のエラーが出る | BIOS/UEFI で仮想化支援を有効にする |
| VM が極端に遅い、または起動しない（推測: Hyper-V と競合） | 管理者 PowerShell で `bcdedit /set hypervisorlaunchtype off` を実行して再起動する（WSL2 / Hyper-V は使えなくなる。戻すときは `auto`） |
| Guest Additions の版が合わないという警告 | 多くの場合はそのまま動く（Vagrant の警告文にもそう書かれている）。共有フォルダに問題がある場合はゲストで `sudo apt install -y virtualbox-guest-x11` を試す |
| `bootstrap.sh` が `$'\r': command not found` で失敗する | Windows の改行（CRLF）になっている。`.gitattributes` が効く状態で clone し直すか、`git config core.autocrlf input` を設定する |

---

## 6. セキュリティ上の注意

- ログイン情報は既定で `vagrant` / `vagrant`。`KALI_PRIVATE_IP` でホストオンリーネットワークに出す場合や長く使う場合は `passwd` で変更する。
- 攻撃ツールは、自分が管理する環境か、許可を得た対象にだけ使う。

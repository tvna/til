# GitLab EE on Rocky Linux 10 (KVM) — IaC 構築手順

macOS から SSH で到達できる KVM ホストに Rocky Linux 10 の VM を作成し、GitLab Enterprise Edition を構築する。

- VM 作成: **OpenTofu** + `dmacvicar/libvirt` provider（`qemu+sshcmd://` で KVM ホストへ接続）
- OS 初期設定: **cloud-init**（固定 IP、管理ユーザー、SSH 公開鍵）
- GitLab EE 構築: **Ansible**（リポジトリ登録、TLS 証明書、`gitlab.rb`、reconfigure）
- TLS: VM 上で生成したプライベート CA による自己署名証明書（社内 CA 証明書への差し替えも可）

IaC を使わない手動手順は [manual.md](manual.md) を参照。

```
 macOS (作業端末)                       KVM ホスト                          VM: Rocky Linux 10
┌──────────────────┐  ssh (libvirt)  ┌──────────────────────┐          ┌──────────────────────┐
│ tofu apply       │───────────────▶│ libvirt / QEMU        │─ create ▶│ cloud-init           │
│ ansible-playbook │───────────────────────── ssh ─────────────────────▶│ GitLab EE (Omnibus)  │
│ ブラウザ / git   │───────────────────────── https / ssh ─────────────▶│ nginx :443, sshd :22 │
└──────────────────┘                 │ br0 (ブリッジ)        │          └──────────────────────┘
                                     └──────────────────────┘
```

---

## 1. 前提（一次情報で確認した事実）

2026-09-30 時点で確認。

| 項目 | 内容 | 出典 |
|---|---|---|
| GitLab の対応 OS | AlmaLinux / RHEL / Oracle Linux 8・9・10 と「Any distribution compatible with a supported Red Hat Enterprise Linux version」。**Rocky Linux の名前は明記されていない** | [Install the Linux package on AlmaLinux and RHEL-compatible distributions](https://docs.gitlab.com/install/package/almalinux/) |
| EL10 への対応開始 | AlmaLinux 10 / RHEL 10 は GitLab 18.6.0 以降 | [Supported platforms](https://docs.gitlab.com/install/package/) |
| ハードウェア要件 | 8 vCPU・メモリ 16 GB がベースライン（制約環境では最低 8 GB）、ストレージ 40 GB 以上。swap は可能なら無効化 | [Installation requirements](https://docs.gitlab.com/install/requirements/) |
| Rocky Linux 10 の CPU 要件 | x86-64-v3 が必須（Intel Haswell 世代以降相当） | [Rocky Linux 10 release notes](https://docs.rockylinux.org/10/releases/release_notes/10_0/) / [Test CPU compatibility](https://docs.rockylinux.org/10/gemstones/test_cpu_compat/) |
| libvirt provider | v0.9 系でスキーマが libvirt XML 準拠に全面改訂されている。本構成は v0.9.9 で `tofu validate` 済み | [OpenTofu Registry](https://search.opentofu.org/provider/dmacvicar/libvirt/latest) |
| libvirt の SSH 接続 | `qemu+sshcmd://` は `~/.ssh/config` を使う。リモート側に `virt-ssh-helper` か `nc` が必要 | provider の `docs/transports.md`（v0.9.9） |
| macOS の TLS 要件 | SAN 必須、EKU に serverAuth が必要、有効期間は 825 日以下、RSA は 2048 bit 以上、署名は SHA-2 | [Apple: Requirements for trusted certificates](https://support.apple.com/en-us/103769) |
| 最新版（確認時点） | Rocky 10 GenericCloud イメージは `10.2-20260525.0`、GitLab EE の el/10 パッケージは `19.4.1-ee.0.el10` | dl.rockylinux.org / packages.gitlab.com のリポジトリメタデータ |

**推測:** Rocky Linux は RHEL 互換ディストリビューションなので、GitLab の対応範囲「RHEL 互換」に含まれると考えられる。ただし GitLab のドキュメントは Rocky を名指ししていない。

---

## 2. ディレクトリ構成

```
gitlab-ee-kvm/
├── README.md                     # この手順書（IaC）
├── manual.md                     # 手動手順書
├── Makefile                      # make init / apply / provision / destroy
├── terraform/                    # VM 作成（OpenTofu / Terraform）
│   ├── versions.tf               # provider 定義
│   ├── variables.tf
│   ├── main.tf                   # volume / cloud-init / domain / inventory 生成
│   ├── outputs.tf
│   ├── terraform.tfvars.example  # ← コピーして terraform.tfvars を作る
│   ├── .terraform.lock.hcl       # darwin_arm64 / darwin_amd64 / linux_amd64 のハッシュ入り
│   └── templates/                # cloud-init / inventory テンプレート
└── ansible/                      # GitLab EE 構築
    ├── ansible.cfg
    ├── requirements.yml          # ansible.posix / community.crypto / community.general
    ├── site.yml
    ├── inventory/hosts.yml       # ← OpenTofu が生成（git 管理外）
    ├── group_vars/gitlab/main.yml
    └── roles/
        ├── common/               # パッケージ、タイムゾーン、firewalld
        ├── gitlab_tls/           # プライベート CA とサーバー証明書
        └── gitlab/               # リポジトリ、gitlab.rb、インストール、reconfigure
```

---

## 3. 手順

### 3.1 KVM ホストの準備（初回のみ）

以下の例は KVM ホストが RHEL 系（Rocky / Alma / RHEL 9・10）の場合。KVM ホストへ SSH ログインして実行する。

1. **CPU が x86-64-v3 に対応しているか確認する**（VM には `host-passthrough` でホスト CPU をそのまま渡す）

   ```bash
   /lib64/ld-linux-x86-64.so.2 --help | grep x86-64-v3
   # "x86-64-v3 (supported, searched)" と表示されれば OK
   ```

2. **libvirt を入れて有効化する**

   ```bash
   sudo dnf install -y qemu-kvm libvirt virt-install
   sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket
   # nc 経由で接続する場合や、モノリシックな libvirtd 前提のクライアントを使う場合は virtproxyd も有効化する
   sudo systemctl enable --now virtproxyd.socket
   command -v virt-ssh-helper   # sshcmd 接続で使う
   ```

3. **SSH 接続ユーザーを libvirt グループに入れる**（`qemu:///system` を sudo なしで操作するため）

   ```bash
   sudo usermod -aG libvirt "$USER"
   # 再ログイン後に確認
   virsh -c qemu:///system list --all
   ```

4. **ストレージプール `default` を確認する**

   ```bash
   virsh -c qemu:///system pool-list --all
   # 無ければ作成
   sudo virsh pool-define-as default dir --target /var/lib/libvirt/images
   sudo virsh pool-build default && sudo virsh pool-start default && sudo virsh pool-autostart default
   ```

5. **ブリッジ `br0` を用意する**（LAN 上の macOS から VM へ直接到達させる場合）

   > ⚠ SSH 接続中に物理 NIC の設定を変えると切断されることがある。コンソールから作業するか、IPMI などの帯域外管理を用意しておく。

   ```bash
   # 例: 物理 NIC が eno1、ホストの IP が 192.168.10.10/24 の場合
   sudo nmcli con add type bridge ifname br0 con-name br0 \
     ipv4.method manual ipv4.addresses 192.168.10.10/24 \
     ipv4.gateway 192.168.10.1 ipv4.dns 192.168.10.1 bridge.stp no
   sudo nmcli con add type ethernet ifname eno1 master br0 con-name br0-port-eno1
   sudo nmcli con down "<既存の eno1 の接続名>" ; sudo nmcli con up br0
   ```

   ブリッジを作れない場合は、libvirt の `default` ネットワーク（NAT）を使い、KVM ホストを踏み台にする（3.3 参照）。

### 3.2 macOS の準備

1. **ツールを入れる**（Homebrew。Terraform は homebrew-core に無いため OpenTofu を使う）

   ```bash
   brew install opentofu ansible
   brew install ansible-lint   # 任意: make lint で使う
   tofu version && ansible --version
   ```

   Terraform を使う場合は `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` を実行し、`make` 実行時に `TOFU=terraform` を指定する。

2. **SSH 鍵と `~/.ssh/config` を用意する**

   `qemu+sshcmd://` は `BatchMode=yes` で ssh を起動する。そのため、パスフレーズ付きの鍵は事前に ssh-agent へ登録しておく。

   ```bash
   [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519
   ssh-copy-id <kvm-user>@<kvm-host-ip>
   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
   ```

   `~/.ssh/config`:

   ```sshconfig
   Host kvm-host
     HostName 192.168.10.10
     User kvmadmin
     IdentityFile ~/.ssh/id_ed25519
     AddKeysToAgent yes
     UseKeychain yes
   ```

3. **疎通を確認する**

   ```bash
   ssh kvm-host virsh -c qemu:///system list --all
   ```

### 3.3 変数を設定する

```bash
cd gitlab-ee-kvm
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vi terraform/terraform.tfvars
```

| 変数 | 説明 |
|---|---|
| `libvirt_uri` | `qemu+sshcmd://kvm-host/system`（`kvm-host` は `~/.ssh/config` の Host 名） |
| `network_mode` / `network_name` | ブリッジなら `bridge` / `br0`、NAT なら `network` / `default` |
| `ip_address` / `gateway` / `dns_servers` | VM の固定 IP 設定 |
| `ansible_proxy_jump` | NAT 構成で macOS から VM へ直接届かない場合に `kvm-host` を指定 |
| `fqdn` | GitLab の FQDN。`external_url` と証明書の SAN に使う |
| `vm_vcpu` / `vm_memory_mib` / `vm_disk_gib` | 既定は 8 vCPU / 16 GiB / 100 GiB |

GitLab 側の設定は `ansible/group_vars/gitlab/main.yml` で変更する。

| 変数 | 既定値 | 説明 |
|---|---|---|
| `gitlab_version` | `""`（最新） | 固定する場合は `"19.4.1-ee.0.el10"` のように指定 |
| `gitlab_memory_constrained` | `false` | メモリ 8 GB 程度で動かす場合に `true` |
| `gitlab_tls_mode` | `selfsigned` | 社内 CA の証明書を使う場合は `provided` |
| `gitlab_extra_config` | `""` | SMTP などの追加設定を `gitlab.rb` に追記する |

root の初期パスワードを指定する場合は ansible-vault を使う（指定しない場合は GitLab が自動生成する）。GitLab のパスワード要件（8 文字以上、よく使われるパスワードは不可）を満たす値にすること。

```bash
cd ansible
ansible-vault create group_vars/gitlab/vault.yml
# 中身: vault_gitlab_root_password: "十分に長いパスワード"
```

### 3.4 VM を作成する（OpenTofu）

```bash
make init    # provider と Ansible collection を取得
make plan
make apply
```

- ベースイメージ（約 545 MB）は provider が **macOS 側でダウンロードし**、libvirt 経由で KVM ホストのプールへ転送する。
- `apply` が終わると `ansible/inventory/hosts.yml` が生成される。
- cloud-init の設定（`templates/user-data.yaml.tftpl`）は初回起動時にだけ反映される。VM 作成後に変更しても、動いている VM には反映されない。
- ⚠ **VM 作成後に `base_image_url` を変更しないこと。** ベースイメージのボリュームが作り直され、それを backing file にしているルートディスクも作り直しになる（データが消える）。

### 3.5 GitLab EE を構築する（Ansible）

```bash
make provision
# vault を使う場合
make provision ANSIBLE_ARGS="--ask-vault-pass"
```

Playbook の処理順:

1. SSH 接続と `cloud-init status --wait` の完了を待つ。OS が Rocky Linux 10 であることを確認する
2. `common`: curl / chrony / firewalld / python3-cryptography を導入し、ssh・http・https を開放する
3. `gitlab_tls`: `/root/gitlab-ca` にプライベート CA、`/etc/gitlab/ssl/<fqdn>.{crt,key}` にサーバー証明書を作る。CA は `/etc/gitlab/trusted-certs` と OS の信頼ストアに登録し、macOS 側の `artifacts/gitlab-ca.crt` へ回収する
4. `gitlab`: packages.gitlab.com の el/10 リポジトリを登録して `gitlab-ee` をインストールする。`gitlab.rb` を配置して `gitlab-ctl reconfigure` を実行し、`/-/readiness` が 200 を返すまで待つ

再実行しても結果は変わらない（冪等）。サーバー証明書は残り 30 日を切ると再発行される。

### 3.6 macOS からアクセスできるようにする

1. **名前解決**（社内 DNS に登録しない場合）

   ```bash
   echo "192.168.10.50 gitlab.lab.example" | sudo tee -a /etc/hosts
   ```

2. **プライベート CA を信頼する**（Safari / Chrome はシステムキーチェーンを参照する）

   ```bash
   sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain artifacts/gitlab-ca.crt
   ```

3. **git クライアントに CA を指定する**（キーチェーンを参照しない git のビルド向け）

   ```bash
   git config --global http."https://gitlab.lab.example/".sslCAInfo "$PWD/artifacts/gitlab-ca.crt"
   ```

### 3.7 初回ログイン

- URL: `https://<fqdn>`、ユーザー: `root`
- パスワード: vault で指定した値。指定していない場合は VM 上で確認する（**24 時間で自動削除**される）

  ```bash
  ssh admin@192.168.10.50 sudo cat /etc/gitlab/initial_root_password
  ```

ログインしたら root のパスワードを変更し、Admin Area で新規登録の制限などを設定する。EE のサブスクリプションは別途適用する。

---

## 4. 運用

| 作業 | 方法 |
|---|---|
| 設定変更 | `group_vars/gitlab/main.yml` を編集して `make provision`（`gitlab.rb` は Ansible が管理する。VM 上で直接編集しても次回の実行で上書きされる） |
| アップグレード | `gitlab_version` を上げて `make provision`。メジャーバージョンをまたぐ場合は [Upgrade paths](https://docs.gitlab.com/update/upgrade_paths/) の必須停止点を順に踏む |
| バックアップ | `sudo gitlab-backup create`。`/etc/gitlab/gitlab-secrets.json` と `/etc/gitlab/gitlab.rb` は別途退避する（[Back up GitLab](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/)） |
| 証明書の更新 | `make provision`（残り 30 日未満で自動再発行） |
| 削除 | `make destroy`（VM、ルートディスク、cloud-init ISO、ベースイメージを削除） |

---

## 5. トラブルシュート

| 症状 | 確認すること |
|---|---|
| `tofu apply` で libvirt に接続できない | `ssh kvm-host virsh -c qemu:///system list` が通るか。ssh-agent に鍵が登録済みか（BatchMode のためパスフレーズ入力不可）。`virt-ssh-helper` があるか |
| VM がすぐ停止する、カーネルパニックになる | ホスト CPU の x86-64-v3 対応（3.1-1）。`virsh dumpxml gitlab` で `<cpu mode='host-passthrough'>` になっているか |
| Ansible が SSH 接続を待ったまま終わらない | IP・ゲートウェイ・ブリッジ名。KVM ホストで `virsh domifaddr gitlab --source arp` |
| cloud-init が失敗する | VM 上で `sudo cloud-init status --long`、`/var/log/cloud-init.log` |
| VM を作り直したら Ansible が `Host key verification failed` で止まる | 古いホスト鍵が残っている。`ssh-keygen -R <VM の IP>` |
| しばらくしてから `tofu plan` すると `libvirt_cloudinit_disk` の再作成が出る | provider は cloud-init ISO を macOS の一時ディレクトリに置いており、ファイルが消えると再作成になる（provider のソースで確認）。ISO のパスは内容のハッシュで決まるので、VM やディスクへの影響は無い見込み（推測） |
| reconfigure が失敗する | VM 上で `sudo gitlab-ctl reconfigure` を再実行してログを確認。`sudo gitlab-ctl tail` |
| VM のコンソールを見たい | VNC は KVM ホストの 127.0.0.1 で待ち受けている。`ssh kvm-host virsh -c qemu:///system vncdisplay gitlab` で番号を確認し、`ssh -L 5900:127.0.0.1:5900 kvm-host` を張って `open vnc://localhost:5900`。管理ユーザーはパスワードロック済みなので、コンソールからのログインには別途パスワード設定が必要 |

---

## 6. 検証状況（事実と推測の区別）

**事実（実施済み）**

- `tofu fmt -check` と `tofu validate` が通った（OpenTofu 1.13.0 / libvirt provider 0.9.9 / local provider 2.9.1）
- cloud-init・network-config・inventory の各テンプレートを描画し、YAML として読み込めることを確認した
- `ansible-playbook --syntax-check` と `ansible-lint --profile production` が通った（ansible-core 2.19）
- `gitlab_tls` ロールをローカルで 2 回実行した。2 回目は changed=0 だった。生成した証明書を `openssl verify` で検証し、SAN・EKU・有効期間 397 日であることを確認した
- 必要なパッケージ（curl, chrony, firewalld, python3-firewall, python3-cryptography）が Rocky 10 の BaseOS に存在することを、リポジトリのメタデータで確認した
- 初回インストールの挙動を omnibus-gitlab のパッケージスクリプトで確認した。`EXTERNAL_URL` を渡さずにインストールするとパッケージは reconfigure を実行しない。本構成はこの挙動を前提に、reconfigure を Ansible から明示的に実行している

**未検証**

- 実際の KVM ホストでの `tofu apply`、Rocky 10 VM 上での Playbook の実行、GitLab の起動（この構成を作った環境には KVM ホストが無いため）

**推測・注意**

- Rocky Linux は「RHEL 互換」として GitLab の対応範囲に含まれると考えられる（前述のとおり名指しはされていない）
- libvirt provider は 1.0 未満であり、今後のバージョンでスキーマが変わる可能性がある。`.terraform.lock.hcl` と `~> 0.9.9` の指定で固定している
- ブリッジ作成手順（3.1-5）は NetworkManager の構成や NIC 名に依存する

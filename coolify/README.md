# Coolify on Rocky Linux (KVM)

macOS から SSH 経由で KVM ホストに Rocky Linux VM を作成し、Coolify を構築する手順と IaC。

- **Terraform** (`dmacvicar/libvirt` v0.9.x): VM・ディスク・cloud-init を作成
- **Ansible**: OS 初期設定 → Docker Engine → Coolify 公式インストーラ実行
- アクセス方式: LAN 内 IP 直接 (`http://<VM-IP>:8000`)

```
macOS (terraform / ansible)
  │  SSH (qemu+sshcmd)            SSH (ansible)
  ▼                               ▼
KVM ホスト ── br0 ── LAN ── Rocky Linux VM (固定 IP)
  libvirtd                          ├─ firewalld / sshd 設定
                                    ├─ Docker CE
                                    └─ Coolify (:8000 / :6001 / :6002, proxy :80 / :443)
```

## ディレクトリ構成

```
coolify/
├── README.md                      # この手順書
├── terraform/
│   ├── versions.tf                # provider 定義
│   ├── variables.tf
│   ├── main.tf                    # volume / cloud-init / domain / inventory 生成
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── templates/
│       ├── user-data.yaml.tftpl   # 管理ユーザー・SSH 鍵
│       └── network-config.yaml.tftpl  # 固定 IP
└── ansible/
    ├── ansible.cfg
    ├── requirements.yml
    ├── inventory.ini.example      # Terraform を使わない場合用
    ├── site.yml
    ├── group_vars/coolify_hosts.yml
    └── roles/{base,docker,coolify}/
```

## 0. 前提条件

### KVM ホスト

| 項目 | 確認コマンド (KVM ホスト上) |
| --- | --- |
| libvirtd が稼働 | `systemctl is-active libvirtd` (またはモジュラーデーモン `virtqemud`) |
| SSH ユーザーが `qemu:///system` を操作可能 | `virsh -c qemu:///system list --all` (sudo なしで成功すること。通常は `libvirt` グループ所属) |
| ストレージプール `default` が存在 | `virsh pool-list --all` |
| LAN 接続ブリッジ (例: `br0`) が存在 | `ip -br link show type bridge` |
| `virt-ssh-helper` または `nc` がある | `command -v virt-ssh-helper nc` |

ブリッジが無い場合の作成例 (ホストが NetworkManager 管理の場合。**SSH が切れる可能性があるためコンソールから実施**):

```bash
# enp1s0 は物理 NIC 名に置き換える
nmcli con add type bridge ifname br0 con-name br0 ipv4.method auto
nmcli con add type bridge-slave ifname enp1s0 master br0
nmcli con up br0
```

### macOS (作業端末)

```bash
# Terraform: homebrew-core には無いので HashiCorp 公式 tap を使う
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install ansible

terraform version   # >= 1.6
ansible --version
```

SSH 鍵と `~/.ssh/config` (KVM ホストへ鍵でログインできること):

```sshconfig
Host kvm-host
  HostName 192.168.1.10
  User youruser
  IdentityFile ~/.ssh/id_ed25519
```

```bash
ssh kvm-host virsh -c qemu:///system list --all   # 疎通確認
```

### VM のサイジング (Coolify 公式最小要件)

| 項目 | 公式最小 | 本 IaC の既定値 |
| --- | --- | --- |
| CPU | 2 cores | 2 vCPU |
| RAM | 2 GB | 4 GiB |
| Disk | 10 GB 空き | 40 GiB |
| Arch | amd64 / arm64 | x86_64 |

## 1. VM を作成する (Terraform)

```bash
cd coolify/terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars   # libvirt_uri / vm_ip_cidr / gateway / dns_servers / bridge_name を環境に合わせる

terraform init
terraform plan
terraform apply
```

`apply` 完了で以下が作成されます。

- Rocky Linux GenericCloud ベースイメージ + CoW ルートディスク
- cloud-init ISO (ホスト名・管理ユーザー `rocky`・SSH 公開鍵・固定 IP)
- VM (`cpu host-passthrough`, `autostart = true`)
- `ansible/inventory.ini` (Ansible 用インベントリ)

起動確認:

```bash
ssh rocky@$(terraform output -raw vm_ip) 'cloud-init status --wait && hostnamectl'
```

> Rocky Linux 10 を使う場合は `rocky_image_url` を差し替える。Rocky 10 (x86_64) は x86-64-v3 CPU が必須のため、`host-passthrough` を外さないこと。

## 2. Coolify を構築する (Ansible)

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml

# 初期管理者 (シェル履歴に残さないよう read で入力)
export COOLIFY_ROOT_USERNAME=admin
export COOLIFY_ROOT_USER_EMAIL=you@your-domain.example
read -rs COOLIFY_ROOT_USER_PASSWORD && export COOLIFY_ROOT_USER_PASSWORD

ansible coolify_hosts -m ping
ansible-playbook site.yml
```

Playbook の処理内容:

| ロール | 内容 |
| --- | --- |
| `base` | cloud-init 完了待ち / `dnf upgrade` / 基本パッケージ / TZ / chronyd / sshd (`PermitRootLogin prohibit-password`, パスワード認証無効) / firewalld で 22,80,443,8000,6001,6002 開放 |
| `docker` | podman・runc 削除 → Docker CE 公式 RHEL リポジトリから導入 |
| `coolify` | 初期管理者の値を検証 → `install.sh` を環境変数付きで実行 (`/data/coolify/source/.env` があればスキップ) → `/api/health` が 200 になるまで待機 |

### 初期管理者の制約 (重要)

Coolify は `ROOT_USER_EMAIL` / `ROOT_USER_PASSWORD` が **検証に失敗すると管理者を作らず黙ってスキップ**し、登録画面が開いたままになります。登録画面に最初に到達した人がサーバーの root 権限を持つ管理者になるため、次を満たしてください。

- パスワード: 8 文字以上・大文字・小文字・数字・記号を含み、漏洩パスワード DB に載っていないこと
- メール: RFC 準拠かつ **DNS 上に存在するドメイン** (`*.local` などは不可)
- ユーザー名: 3 文字以上、英数字・空白・`_`・`-` のみ

Ansible 側で長さ・文字種は事前チェックしますが、「漏洩 DB 照合」と「ドメインの DNS 存在確認」はチェックしていません。

## 3. 動作確認

1. ブラウザで `http://<VM-IP>:8000` を開き、設定したメールアドレスでログインできること
2. `http://<VM-IP>:8000/register` で新規登録できないこと (できる場合は管理者作成に失敗しているので、すぐに自分で登録する)
3. VM 上で確認:

```bash
ssh rocky@<VM-IP>
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
curl -s http://127.0.0.1:8000/api/health
```

## 4. 運用

| 作業 | 方法 |
| --- | --- |
| Coolify 更新 | 既定で自動更新 (`coolify_autoupdate: "true"`)。手動なら UI の Settings から |
| バージョン固定で新規構築 | `group_vars/coolify_hosts.yml` の `coolify_version` を指定 |
| OS 更新 | `ansible-playbook site.yml` を再実行 (Coolify 再インストールはスキップされる) |
| VM 削除 | `cd terraform && terraform destroy` (**Coolify のデータも消える**) |
| バックアップ | Coolify UI の S3 バックアップ設定、または `/data/coolify` と `coolify-db` ボリュームを退避 |

## 5. セキュリティ上の注意

- **Docker で公開したポートは firewalld の INPUT ルールを経由しない**。Docker は nat テーブルでコンテナへ振り向けるため、firewalld でポートを閉じても Coolify が publish したポート (8000 等) は到達可能なままです。LAN 外に出すなら上流のルーター/FW で制御してください。
- Coolify は自身の SSH 鍵を `root` の `authorized_keys` に登録し、`host.docker.internal` 経由で root SSH します。`PermitRootLogin no` にすると Coolify がサーバーを管理できなくなります。
- ドメイン + Coolify proxy 経由でダッシュボードにアクセスできるようになったら、8000/6001/6002 の公開は閉じてよい (公式ドキュメント記載)。

## 6. トラブルシューティング

| 症状 | 確認 |
| --- | --- |
| `terraform apply` が libvirt に接続できない | `ssh kvm-host virsh -c qemu:///system list` が通るか。`libvirt_uri` に `?proxy=netcat` を付けて切り分け |
| VM に SSH できない | KVM ホストで `virsh console coolify` (抜けるのは `Ctrl + ]`)。`/var/log/cloud-init.log`、`ip -br a` を確認 |
| NIC 名が eth0 でない | `variables.tf` の `nic_name` を実際の名前に変更して再作成 |
| インストールが失敗 (出力は `no_log` で非表示) | VM の `/data/coolify/source/installation-*.log` |
| Docker サブネットが LAN と衝突 | `coolify_docker_address_pool_base` を変更 (例: `172.30.0.0/16`) |

## 事実と推測の区別

**事実 (一次情報で確認)**

- Coolify 公式インストーラは Rocky Linux を対応 OS に含み、`rocky` の場合は `https://download.docker.com/linux/rhel/docker-ce.repo` から Docker を導入する (`install.sh`)
- インストーラは `ROOT_USERNAME` / `ROOT_USER_EMAIL` / `ROOT_USER_PASSWORD` / `AUTOUPDATE` / `DOCKER_ADDRESS_POOL_BASE` / `DOCKER_ADDRESS_POOL_SIZE` を受け付け、第 1 引数でバージョンを指定できる (`install.sh`)
- 初期管理者の検証ルールと、失敗時にスキップする挙動 (`database/seeders/RootUserSeeder.php`)
- 必要ポート 22/80/443 と、IP 直接アクセス時の 8000/6001/6002 (公式 Firewall ドキュメント)
- sshd の要件 `PubkeyAuthentication yes` / `PermitRootLogin prohibit-password` (公式 OpenSSH ドキュメント)
- `GET /api/health` のルートが存在する (`routes/api.php`)
- Docker の公開ポートは nat テーブルで振り向けられ INPUT チェーンを経由しない (Docker 公式ドキュメント)
- Terraform 構成は `terraform validate`、Ansible は `ansible-playbook --syntax-check` / `ansible-lint` (production profile) を通過 (2026-09-30 時点。実機での apply / 実行は未検証)

**推測 (未検証)**

- Rocky GenericCloud イメージの NIC 名は `eth0` (カーネル引数 `net.ifnames=0` 前提)
- `create.content.url` のイメージは Terraform 実行端末 (macOS) でダウンロードされ、SSH 越しに KVM ホストへアップロードされる (約 1 GB の転送が発生する)
- SELinux enforcing のままで Coolify が動作する (Docker の既定 `selinux-enabled: false` のため)

## 参考 (一次情報)

- Coolify Installation: https://coolify.io/docs/get-started/installation
- Coolify Firewall: https://coolify.io/docs/knowledge-base/server/firewall
- Coolify OpenSSH: https://coolify.io/docs/knowledge-base/server/openssh
- Coolify install.sh: https://github.com/coollabsio/coolify/blob/v4.x/scripts/install.sh
- terraform-provider-libvirt: https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs
- Rocky Linux cloud images: https://dl.rockylinux.org/pub/rocky/9/images/x86_64/
- Docker packet filtering and firewalls: https://docs.docker.com/engine/network/packet-filtering-firewalls/

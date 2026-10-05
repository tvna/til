# BPMN 業務分析・運用自動化基盤 on Rocky Linux (KVM)

macOS から SSH 経由で KVM ホストに Rocky Linux VM を作成し、次の 2 つを同じ VM に構築する手順と IaC。

- **Apache KIE Sandbox**: BPMN の作図・レビュー (業務分析)
- **Semaphore UI**: Ansible 実行基盤 (運用自動化)。日本語 UI、Active Directory / LDAP 連携に対応

構築手段:

- **Terraform** (`dmacvicar/libvirt` v0.9.x): VM・ディスク・cloud-init を作成
- **Ansible**: OS 初期設定 → Docker Engine → KIE Sandbox / Semaphore UI (Docker Compose) 起動
- アクセス方式: LAN 内 IP 直接 (KIE Sandbox `http://<VM-IP>:9090`、Semaphore UI `http://<VM-IP>:3000`)

```
macOS (terraform / ansible / ブラウザ)
  │  SSH (qemu+sshcmd)            SSH (ansible)          HTTP (ブラウザ)
  ▼                               ▼                       ▼
KVM ホスト ── br0 ── LAN ── Rocky Linux VM (固定 IP)
  libvirtd                          ├─ firewalld / sshd 設定
                                    ├─ Docker CE
                                    ├─ KIE Sandbox (docker compose)
                                    │    ├─ webapp            :9090  … BPMN/DMN エディタ
                                    │    ├─ extended services :21345 … 検証・DMN 実行
                                    │    └─ CORS proxy        :7081  … ブラウザ → GitHub の Git 通信を中継
                                    └─ Semaphore UI (docker compose)
                                         ├─ server            :3000  … Ansible 実行・承認・履歴
                                         └─ PostgreSQL 17           … 外部非公開
```

## 全体の進め方 (分析 → 自動化 → 改善)

| 段階 | やること | ツール |
| --- | --- | --- |
| 1. 分析 | 現行業務 (As-Is) を BPMN で描き、手作業・待ち・判断のタスクに印を付ける。GitHub の PR でレビュー | KIE Sandbox |
| 2. 自動化 | 自動化できるタスクを Ansible Playbook にし、Semaphore UI のテンプレートとして登録。BPMN のタスク名と Semaphore のテンプレート名を一致させて対応を追えるようにする | Semaphore UI |
| 3. 改善 | 実行履歴 (所要時間・失敗率) を既存の Prometheus / Grafana で可視化し、BPMN (To-Be) を更新する | Semaphore UI の履歴、既存の監視基盤 |

> 3. の実行履歴の取り込み方法 (Semaphore の API / DB から指標化) は本 IaC には含まない。

## ツール選定の経緯

当初は Flowable を検討したが、目的が「BPMN による業務分析と運用自動化」であり、日本のエンタープライズ利用を見越して、作図と自動化を別ツールに分けた。

### 作図 (業務分析)

| 候補 | 判断 |
| --- | --- |
| Flowable | GUI モデラーを含む `flowable/flowable-ui` は 6.8.0 (2022-12) が最終。最新 `flowable-rest` 8.0.0 は API のみで作図画面が無い |
| Camunda 7 CE | 2025-10 の 7.24 で Community Edition は EOL |
| Camunda 8 | 8.6 以降、Self-Managed の本番利用に有償ライセンスが必要 |
| draw.io | BPMN 図形は描けるが BPMN 2.0 XML としては扱えない見込み |
| **KIE Sandbox** | Apache 2.0。BPMN 2.0 XML を直接編集でき、GitHub 連携でレビューできる。10.2.0 (2026-04)。**日本語 UI は無い** (英語・ドイツ語のみ) |

### 自動化 (運用)

| 候補 | 判断 |
| --- | --- |
| **Semaphore UI** | MIT。日本語 UI あり。**OSS 版で** LDAP / Active Directory / OpenID Connect に対応。v2.19.14 (2026-09) |
| Rundeck | Apache 2.0。日本語 UI あり。v6.2.1 |
| Kestra | Apache 2.0。日本語 UI あり。ただし SSO・RBAC・監査ログは Enterprise Edition のみ |
| n8n | Sustainable Use License (OSI 承認の OSS ではない) |
| AWX | 2024-07 以降リリース停止中 (README に明記) |
| 国産商用 (intra-mart IM-BPM / Questetra BPM Suite) | BPMN 2.0 対応で日本語サポートあり。費用とベンダーロックインを理由に今回は見送り |

## ディレクトリ構成

```
kie-sandbox/
├── README.md                      # この手順書
├── terraform/                     # coolify/terraform と同じ構成 (VM 名・サイズのみ変更)
│   ├── versions.tf / variables.tf / main.tf / outputs.tf
│   ├── terraform.tfvars.example
│   └── templates/{user-data,network-config}.yaml.tftpl
└── ansible/
    ├── ansible.cfg
    ├── requirements.yml
    ├── inventory.ini.example      # Terraform を使わない場合用
    ├── site.yml
    ├── group_vars/kie_sandbox_hosts.yml
    └── roles/
        ├── base/                  # dnf 更新・firewalld・sshd 強化
        ├── docker/                # Docker CE
        ├── kie_sandbox/           # compose.yaml 配置・起動・疎通確認
        └── semaphore/             # 秘密情報生成・compose.yaml 配置・起動・疎通確認
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

### VM のサイジング

| 項目 | 既定値 | 根拠 |
| --- | --- | --- |
| CPU | 2 vCPU | |
| RAM | 6 GiB | KIE Extended Services (Java) と Semaphore UI + PostgreSQL を同居させる |
| Disk | 30 GiB | OS + コンテナイメージ 3 つ |
| Arch | x86_64 | 公式イメージは amd64 のみ (arm64 なし) |

## 1. VM を作成する (Terraform)

```bash
cd kie-sandbox/terraform
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

> 既に `coolify/` で VM を作っている KVM ホストでも、`vm_name` が異なれば共存できる (ベースイメージも VM 名ごとに別ボリュームになる)。

## 2. KIE Sandbox と Semaphore UI を構築する (Ansible)

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml

# Semaphore UI の初期管理者 (シェル履歴に残さないよう read で入力。12 文字以上)
export SEMAPHORE_ADMIN_USERNAME=admin
export SEMAPHORE_ADMIN_EMAIL=you@example.com
read -rs SEMAPHORE_ADMIN_PASSWORD && export SEMAPHORE_ADMIN_PASSWORD

ansible kie_sandbox_hosts -m ping
ansible-playbook site.yml
```

| ロール | 内容 |
| --- | --- |
| `base` | cloud-init 完了待ち / `dnf upgrade` / 基本パッケージ / TZ / chronyd / sshd (root ログイン禁止・パスワード認証無効) / firewalld で 22,9090,21345,7081,3000 開放 |
| `docker` | podman・runc 削除 → Docker CE 公式 RHEL リポジトリから導入 |
| `kie_sandbox` | `/opt/kie-sandbox/compose.yaml` を配置 → `docker compose up --wait` → 3 サービスの HTTP 応答を確認 |
| `semaphore` | DB パスワードと鍵暗号化キーを VM 上で初回のみ生成 (`/opt/semaphore/generated.env`) → 管理者・LDAP パスワードを `admin.env` (server のみ参照) に配置 → `compose.yaml` 配置 → 起動 → `/api/ping` を確認 |

主な変数 (`group_vars/kie_sandbox_hosts.yml`):

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `kie_sandbox_version` | `10.2.0` | 3 イメージ共通のタグ |
| `kie_sandbox_public_host` | `ansible_host` (VM の IP) | **ブラウザで開くホスト名/IP**。DNS 名で開くならその名前にする |
| `kie_sandbox_cors_allowed_hosts` | `github.com`, `*.github.com`, `*.githubusercontent.com` | CORS proxy の転送先。GitLab 等を使うなら追加 |
| `semaphore_version` | `v2.19.14` | Semaphore UI のイメージタグ |
| `semaphore_admin_*` | 環境変数から取得 | 初期管理者。**初回起動時のみ反映**され、後から変えても変わらない |
| `semaphore_ldap_enabled` ほか | `false` | Active Directory / LDAP 連携。設定例は `group_vars` のコメントを参照 |

### 設定上のポイント

- webapp はブラウザ上で動くため、Extended Services と CORS proxy の URL は **ブラウザから届くアドレス** を渡す必要がある。公式 compose は `localhost` 固定なので、本 IaC では `kie_sandbox_public_host` から組み立てている。
- CORS proxy は `CORS_PROXY_ALLOWED_ORIGINS` に KIE Sandbox の URL (`http://<VM-IP>:9090`) を設定しないと Git 連携が動かない。ブラウザで開く URL と 1 文字でも違う (IP と DNS 名など) と拒否される。

## 3. 動作確認

### KIE Sandbox

1. ブラウザで `http://<VM-IP>:9090` を開く
2. トップ画面から BPMN を新規作成し、要素を配置できること
3. エディタ上部の Extended Services の表示が「接続済み」になること
4. VM 上で確認 (どちらも HTTP 200 が返ること):

```bash
ssh rocky@<VM-IP>
sudo docker compose -f /opt/kie-sandbox/compose.yaml ps
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:21345/ping
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7081/ping
```

### Semaphore UI

1. ブラウザで `http://<VM-IP>:3000` を開き、初期管理者でログインできること
2. 言語設定で日本語を選べること (メニューの位置は実画面で未確認)
3. VM 上で確認:

```bash
sudo docker compose -f /opt/semaphore/compose.yaml ps
curl -s http://127.0.0.1:3000/api/ping; echo   # pong
```

## 4. 作図・レビューの運用

KIE Sandbox はサーバー側に図を保存しない。**作成した図はブラウザ (IndexedDB) に保存**されるため、共有・レビューは GitHub 経由で行う。

1. GitHub で Personal Access Token を作成 (対象リポジトリへの書き込み権限)
2. KIE Sandbox 右上のアカウントメニュー (Connected accounts) から GitHub を選び、トークンを登録
3. 既存リポジトリの URL を入力してインポートする。または新規作成した図をツールバーの「Share」から GitHub リポジトリ / Gist として保存する
4. 編集 → 「Commit」→ push → GitHub 上で Pull Request を作成してレビュー

> 注意: ブラウザのサイトデータを消すと未 push の図は失われる。こまめに push すること。

## 5. 運用

| 作業 | 方法 |
| --- | --- |
| バージョン更新 | `kie_sandbox_version` を変更して `ansible-playbook site.yml` |
| OS 更新 | `ansible-playbook site.yml` を再実行 |
| 停止 / 起動 | `sudo docker compose -f /opt/{kie-sandbox,semaphore}/compose.yaml stop` / `start` |
| ログ | `sudo docker compose -f /opt/{kie-sandbox,semaphore}/compose.yaml logs -f` |
| Semaphore のバックアップ | `sudo docker compose -f /opt/semaphore/compose.yaml exec db pg_dump -U semaphore semaphore > semaphore.sql` と `/opt/semaphore/generated.env` (鍵暗号化キー。失うと登録済みの鍵を復号できない) |
| VM 削除 | `cd terraform && terraform destroy` (**Semaphore の実行履歴・登録情報も消える**。KIE Sandbox の図はサーバーに無い) |

## 6. セキュリティ上の注意

- **KIE Sandbox には認証機能が無い**。URL を知っていれば誰でも開ける。LAN 外に公開しないこと。
- Semaphore UI は SSH 鍵やパスワードを保存する。HTTPS 化 (リバースプロキシ) と AD 連携を本番前に行うこと。本 IaC は HTTP のまま。
- **Docker で公開したポートは firewalld の INPUT ルールを経由しない**。firewalld で閉じても 9090/21345/7081/3000 は到達可能なままなので、LAN 外への公開は上流のルーター/FW で制御する。
- GitHub トークンはブラウザ内に保存される。共用 PC では使わない。
- CORS proxy は許可したホスト (`kie_sandbox_cors_allowed_hosts`) 以外へは転送しない。`*` にすると任意サイトへの踏み台になり得るので避ける。

## 7. トラブルシューティング

| 症状 | 確認 |
| --- | --- |
| `terraform apply` が libvirt に接続できない | `ssh kvm-host virsh -c qemu:///system list` が通るか。`libvirt_uri` に `?proxy=netcat` を付けて切り分け |
| VM に SSH できない | KVM ホストで `virsh console kie-sandbox` (抜けるのは `Ctrl + ]`)。`/var/log/cloud-init.log`、`ip -br a` を確認 |
| Extended Services が未接続表示 | ブラウザから `http://<VM-IP>:21345/ping` が開けるか。`kie_sandbox_public_host` がブラウザで開いたアドレスと一致しているか |
| GitHub への push / import が失敗 | `docker compose logs cors_proxy` で `Origin ... is not allowed` や許可ホスト外のエラーが出ていないか |
| Semaphore UI にログインできない | 初期管理者は初回起動時のみ作成される。`docker compose logs server` を確認。作り直すなら `docker compose down -v` 後に再実行 (**データが消える**) |
| `docker compose up --wait` がタイムアウト | Extended Services の healthcheck 間隔は 1 分。`docker compose ps` で `health: starting` なら待つ。`unhealthy` ならログを確認 |

## 事実と推測の区別

**事実 (一次情報で確認)**

- `flowable/flowable-ui` の最終タグは 6.8.0 (2022-12-23)、`flowable/flowable-rest` の最新は 8.0.0 (2026-02-27) (Docker Hub)
- Flowable 公式リポジトリ main の `docker/` には REST + PostgreSQL の構成のみ。UI 構成は 6.8.0 タグにのみ存在
- KIE Sandbox 10.2.0 の 3 イメージは 2026-04-29 公開、amd64 のみ (Docker Hub)
- 公式 compose は webapp 9090 / Extended Services 21345 / CORS proxy 7081 で公開し、ブラウザ向け URL に `localhost` を使う (`packages/kie-sandbox-distribution`)
- webapp イメージは起動時に環境変数 `KIE_SANDBOX_EXTENDED_SERVICES_URL` / `KIE_SANDBOX_CORS_PROXY_URL` を JSON に変換して配信する (`packages/kie-sandbox-webapp-image`)
- CORS proxy は `CORS_PROXY_ALLOWED_ORIGINS` (`*` 不可) と `CORS_PROXY_ALLOWED_HOSTS` (minimatch、既定 `localhost,*.github.com`) を読む。イメージが設定する `CORS_PROXY_ALLOW_HOSTS` はコードから参照されない (`packages/cors-proxy/src/index.ts`、イメージの config)
- `/ping` は Origin ヘッダー無しでも 200 を返す (`packages/cors-proxy/src/proxy/server.ts`)
- 作業領域はブラウザ内ファイルシステム (LightningFS / IndexedDB) に保存され、GitHub / GitLab / Bitbucket 連携を持つ (`packages/online-editor`)
- 日本語 UI の有無 (翻訳ファイルの有無で確認): Semaphore UI (`web/src/lang/ja.js`)・Rundeck・Kestra はあり。KIE Sandbox・Operaton・n8n は無し
- Semaphore UI v2.19.14 は 2026-09-09 公開。公式 compose は PostgreSQL 構成を提供し、起動スクリプトは `config.json` が無い初回のみ管理者を作成する (`deployment/docker/server/server-wrapper`)
- Semaphore UI は OSS 版で LDAP / OpenID Connect に対応 (公式ドキュメント)。`GET /api/ping` が存在する (`api/router.go`)
- Kestra の SSO・RBAC・監査ログは Enterprise Edition のみ (公式サイト)
- n8n は Sustainable Use License、AWX は 2024-07 以降リリース停止 (各リポジトリ)
- Docker の公開ポートは nat テーブルで振り向けられ INPUT チェーンを経由しない (Docker 公式ドキュメント)
- Terraform 構成は `terraform validate`、Ansible は `ansible-playbook --syntax-check` / `ansible-lint` (production profile) を通過 (2026-10-05 時点。実機での apply / 実行は未検証)

**推測 (未検証)**

- 画面の表記 (メニュー名・ボタン名) は 10.2.0 のソースから拾ったもので、実画面では未確認
- HTTP (非 HTTPS) でも作図・Git 連携は動作する (セキュアコンテキスト必須の API はクラスタ接続ウィザードのクリップボード操作でのみ使用を確認)
- `minimatch("github.com", "*.github.com")` は一致しないため、`github.com` を明示的に許可する必要がある
- 6 GiB のメモリで 5 コンテナが安定動作する
- Semaphore のコンテナ再作成で `config.json` が再生成されても、既存 DB と管理者は維持される
- Rocky GenericCloud イメージの NIC 名は `eth0`

## 参考 (一次情報)

- KIE Sandbox distribution: https://github.com/apache/incubator-kie-tools/tree/10.2.0/packages/kie-sandbox-distribution
- KIE Sandbox webapp image: https://github.com/apache/incubator-kie-tools/tree/10.2.0/packages/kie-sandbox-webapp-image
- CORS proxy: https://github.com/apache/incubator-kie-tools/tree/10.2.0/packages/cors-proxy
- Docker Hub: https://hub.docker.com/r/apache/incubator-kie-sandbox-webapp
- Flowable Docker: https://github.com/flowable/flowable-engine/tree/main/docker
- Camunda 7 CE EOL: https://forum.camunda.io/t/important-update-camunda-7-community-edition-end-of-life-announced/50921
- Camunda 8 licensing: https://camunda.com/blog/2024/04/licensing-update-camunda-8-self-managed/
- terraform-provider-libvirt: https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs
- Semaphore UI compose: https://github.com/semaphoreui/semaphore/tree/v2.19.14/deployment/compose
- Semaphore UI authentication: https://semaphoreui.com/docs/admin-guide/authentication
- Kestra Enterprise Edition: https://kestra.io/docs/configuration-guide/enterprise-edition
- intra-mart IM-BPM: https://www.intra-mart.jp/products/im-bpm.html
- Docker packet filtering and firewalls: https://docs.docker.com/engine/network/packet-filtering-firewalls/

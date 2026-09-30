# GitLab EE on Rocky Linux 10 (KVM) — 手動手順

IaC を使わずに、コマンドを順に実行して構築する手順。IaC 版（[README.md](README.md)）と同じ構成になる。

- KVM ホスト: RHEL 系、libvirt 導入済み、ブリッジ `br0` あり（準備は README の 3.1 を参照）
- 例で使う値: FQDN `gitlab.lab.example`、VM の IP `192.168.10.50/24`、GW / DNS `192.168.10.1`

凡例: 🖥 = macOS、🧱 = KVM ホスト、📦 = GitLab VM

---

## 1. VM を作成する（🧱 KVM ホスト）

### 1.1 イメージとディスクを用意する

```bash
cd /var/lib/libvirt/images
sudo curl -LO https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2
sudo curl -LO https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2.CHECKSUM
sha256sum -c Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2.CHECKSUM

# ベースイメージを backing file にした 100 GiB のルートディスク
sudo qemu-img create -f qcow2 -F qcow2 \
  -b /var/lib/libvirt/images/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2 \
  /var/lib/libvirt/images/gitlab-root.qcow2 100G
```

### 1.2 cloud-init の設定ファイルを作る

`~/gitlab-ci/user-data`（`ssh_authorized_keys` には macOS 側の `~/.ssh/id_ed25519.pub` の中身を貼る）:

```yaml
#cloud-config
hostname: gitlab
fqdn: gitlab.lab.example
prefer_fqdn_over_hostname: true
manage_etc_hosts: true
timezone: Asia/Tokyo
users:
  - name: admin
    groups: [wheel]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... you@mac
ssh_pwauth: false
disable_root: true
```

`~/gitlab-ci/meta-data`:

```yaml
instance-id: gitlab-001
local-hostname: gitlab
```

`~/gitlab-ci/network-config`:

```yaml
version: 2
ethernets:
  primary:
    match:
      macaddress: "52:54:00:6c:3c:01"
    dhcp4: false
    addresses: [192.168.10.50/24]
    routes:
      - to: default
        via: 192.168.10.1
    nameservers:
      addresses: [192.168.10.1]
```

### 1.3 virt-install で起動する

```bash
# rocky10 が一覧にあるか確認する。無ければ --osinfo require=off を使う
virt-install --osinfo list | grep -i rocky

sudo virt-install \
  --name gitlab \
  --vcpus 8 --memory 16384 \
  --cpu host-passthrough \
  --osinfo rocky10 \
  --import \
  --disk path=/var/lib/libvirt/images/gitlab-root.qcow2,format=qcow2,bus=virtio \
  --network bridge=br0,model=virtio,mac=52:54:00:6c:3c:01 \
  --cloud-init user-data=$HOME/gitlab-ci/user-data,meta-data=$HOME/gitlab-ci/meta-data,network-config=$HOME/gitlab-ci/network-config \
  --graphics vnc,listen=127.0.0.1 \
  --noautoconsole

sudo virsh autostart gitlab
```

- `--cpu host-passthrough`: Rocky Linux 10 は x86-64-v3 が必須のため、ホスト CPU の命令セットをそのまま見せる
- `--cloud-init`: virt-install が NoCloud の ISO を作り、初回起動時だけ CD-ROM として接続する（virt-install の man ページに記載）

---

## 2. OS を設定する（📦 VM）

🖥 macOS から接続する:

```bash
ssh admin@192.168.10.50
```

以降は VM 上で実行する。

```bash
# cloud-init の完了を待つ
sudo cloud-init status --wait

# 必要なパッケージ
sudo dnf install -y curl chrony firewalld
sudo systemctl enable --now chronyd firewalld

# ファイアウォール（GitLab 公式手順と同じ）
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=ssh
sudo systemctl reload firewalld
```

---

## 3. TLS 証明書を作る（📦 VM）

プライベート CA を作り、サーバー証明書を発行する。macOS の要件（SAN・serverAuth・825 日以下）を満たすように、有効期間は 397 日にする。

この節のコマンドはすべて root で実行する。

```bash
sudo -i
FQDN=gitlab.lab.example

# --- プライベート CA ---
install -d -m 0700 /root/gitlab-ca
cd /root/gitlab-ca
openssl genrsa -out ca.key 4096
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=GitLab Lab Private CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out ca.crt

# --- サーバー証明書 ---
openssl genrsa -out ${FQDN}.key 3072
openssl req -new -key ${FQDN}.key -subj "/CN=${FQDN}" -out ${FQDN}.csr
cat > server.ext <<EOF
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${FQDN}
authorityKeyIdentifier = keyid,issuer
subjectKeyIdentifier = hash
EOF
openssl x509 -req -in ${FQDN}.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 397 -sha256 -extfile server.ext -out ${FQDN}.crt
openssl verify -CAfile ca.crt ${FQDN}.crt

# --- GitLab が読む場所へ配置（GitLab 公式手順のパス・権限） ---
mkdir -p /etc/gitlab/ssl /etc/gitlab/trusted-certs
chmod 755 /etc/gitlab/ssl
cp ${FQDN}.crt ${FQDN}.key /etc/gitlab/ssl/
chmod 644 /etc/gitlab/ssl/${FQDN}.crt
chmod 600 /etc/gitlab/ssl/${FQDN}.key
cp ca.crt /etc/gitlab/trusted-certs/gitlab-private-ca.crt

# OS の信頼ストアにも登録（VM 内から自分自身へ HTTPS で接続するため）
cp ca.crt /etc/pki/ca-trust/source/anchors/gitlab-private-ca.crt
update-ca-trust extract

exit   # root から抜ける
```

社内 CA で発行済みの証明書を使う場合は、`/etc/gitlab/ssl/<FQDN>.crt`（サーバー証明書 → 中間証明書の順に連結したもの）と `<FQDN>.key` を配置する。

---

## 4. GitLab EE をインストールする（📦 VM）

### 4.1 リポジトリ登録とインストール

```bash
# GitLab 公式のリポジトリ登録スクリプト（Rocky は os=el として判定される）
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.rpm.sh" | sudo bash

# EXTERNAL_URL を付けずにインストールする。
# この場合パッケージは reconfigure を実行しない（Let's Encrypt の自動設定も走らない）
sudo dnf install -y gitlab-ee
# バージョンを固定する場合: sudo dnf install -y gitlab-ee-19.4.1-ee.0.el10
```

`curl | bash` を避ける場合は、`/etc/yum.repos.d/gitlab_gitlab-ee.repo` を直接作る（スクリプトが生成する内容と同じ）:

```ini
[gitlab_gitlab-ee]
name=gitlab_gitlab-ee
baseurl=https://packages.gitlab.com/gitlab/gitlab-ee/el/10/$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://packages.gitlab.com/gpgkey/gpg.key
       https://packages.gitlab.com/gpgkey/gitlab/3D645A26AB9FBD22.pub.gpg
       https://packages.gitlab.com/gpgkey/gitlab/CB947AD886C8E8FD.pub.gpg
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
```

### 4.2 gitlab.rb を設定する

`/etc/gitlab/gitlab.rb` を編集する。既存の `external_url` 行を置き換え、残りの行を追記する。

```ruby
external_url 'https://gitlab.lab.example'

letsencrypt['enable'] = false
nginx['redirect_http_to_https'] = true
nginx['ssl_certificate'] = "/etc/gitlab/ssl/gitlab.lab.example.crt"
nginx['ssl_certificate_key'] = "/etc/gitlab/ssl/gitlab.lab.example.key"

gitlab_rails['time_zone'] = 'Asia/Tokyo'
```

メモリが 8 GB 程度しかない場合は、GitLab 公式の「memory-constrained environments」の設定も追記する:

```ruby
puma['worker_processes'] = 0
sidekiq['concurrency'] = 10
prometheus_monitoring['enable'] = false
```

### 4.3 初回 reconfigure

```bash
# root の初期パスワードを指定する場合（初回の reconfigure だけに有効）
sudo GITLAB_ROOT_PASSWORD='十分に長いパスワード' gitlab-ctl reconfigure
# 指定しない場合
# sudo gitlab-ctl reconfigure

# 起動確認（既定ではヘルスチェックに localhost からアクセスできる）
curl -s -o /dev/null -w '%{http_code}\n' https://gitlab.lab.example/-/readiness   # 200 なら OK
sudo gitlab-ctl status
```

---

## 5. macOS から接続する（🖥 macOS）

```bash
# CA 証明書を取得する
ssh admin@192.168.10.50 sudo cat /root/gitlab-ca/ca.crt > gitlab-ca.crt

# 名前解決（DNS に登録しない場合）
echo "192.168.10.50 gitlab.lab.example" | sudo tee -a /etc/hosts

# CA をシステムキーチェーンで信頼する
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain gitlab-ca.crt

# git クライアントに CA を指定する
git config --global http."https://gitlab.lab.example/".sslCAInfo "$PWD/gitlab-ca.crt"

# 初期パスワード（GITLAB_ROOT_PASSWORD を指定しなかった場合。24 時間で自動削除される）
ssh admin@192.168.10.50 sudo cat /etc/gitlab/initial_root_password
```

ブラウザで `https://gitlab.lab.example` を開き、`root` でログインする。

---

## 6. 後片付け（🧱 KVM ホスト）

```bash
sudo virsh destroy gitlab
sudo virsh undefine gitlab
sudo rm /var/lib/libvirt/images/gitlab-root.qcow2
```

---

## 参考（一次情報）

- GitLab: [Install on AlmaLinux and RHEL-compatible distributions](https://docs.gitlab.com/install/package/almalinux/) / [Supported platforms](https://docs.gitlab.com/install/package/) / [Requirements](https://docs.gitlab.com/install/requirements/)
- GitLab: [Configure SSL for the Linux package](https://docs.gitlab.com/omnibus/settings/ssl/) / [Memory-constrained environments](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/) / [Health check](https://docs.gitlab.com/administration/monitoring/health_check/)
- Rocky Linux: [Release notes 10.0](https://docs.rockylinux.org/10/releases/release_notes/10_0/) / [Test CPU compatibility](https://docs.rockylinux.org/10/gemstones/test_cpu_compat/)
- Apple: [Requirements for trusted certificates in iOS 13 and macOS 10.15](https://support.apple.com/en-us/103769)
- libvirt: [Daemons](https://libvirt.org/daemons.html)
- virt-install: `man virt-install`（`--cloud-init`、`--osinfo`）

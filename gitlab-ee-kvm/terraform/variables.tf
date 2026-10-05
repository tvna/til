# ---------------------------------------------------------------------------
# 接続先 KVM ホスト
# ---------------------------------------------------------------------------
variable "libvirt_uri" {
  description = "libvirt 接続 URI。qemu+sshcmd は macOS の ~/.ssh/config と ssh-agent をそのまま使う"
  type        = string
  default     = "qemu+sshcmd://kvm-host/system"
}

variable "storage_pool" {
  description = "ディスクを配置する libvirt ストレージプール名"
  type        = string
  default     = "default"
}

# ---------------------------------------------------------------------------
# VM スペック
# ---------------------------------------------------------------------------
variable "vm_name" {
  description = "libvirt ドメイン名"
  type        = string
  default     = "gitlab"
}

variable "vm_vcpu" {
  description = "vCPU 数（GitLab 公式のベースラインは 8 vCPU）"
  type        = number
  default     = 8
}

variable "vm_memory_mib" {
  description = "メモリ (MiB)。GitLab 公式のベースラインは 16 GB、最低 8 GB"
  type        = number
  default     = 16384

  validation {
    condition     = var.vm_memory_mib >= 8192
    error_message = "GitLab の最低要件 8 GB (8192 MiB) 以上を指定してください。"
  }
}

variable "vm_disk_gib" {
  description = "ルートディスク容量 (GiB)。リポジトリ・バックアップ分を見込んで指定する"
  type        = number
  default     = 100

  validation {
    condition     = var.vm_disk_gib >= 40
    error_message = "GitLab の最低要件 40 GB 以上を指定してください。"
  }
}

variable "base_image_url" {
  description = "Rocky Linux 10 GenericCloud イメージの URL。再現性のため latest ではなく日付入りのファイルを指定する"
  type        = string
  default     = "https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2"
}

# ---------------------------------------------------------------------------
# ネットワーク
# ---------------------------------------------------------------------------
variable "network_mode" {
  description = "bridge: ホストのブリッジに直結（LAN から直接到達可能） / network: libvirt 仮想ネットワーク（NAT）"
  type        = string
  default     = "bridge"

  validation {
    condition     = contains(["bridge", "network"], var.network_mode)
    error_message = "network_mode は bridge か network を指定してください。"
  }
}

variable "network_name" {
  description = "network_mode=bridge ならブリッジ名 (例: br0)、network なら libvirt ネットワーク名 (例: default)"
  type        = string
  default     = "br0"
}

variable "mac_address" {
  description = "VM の MAC アドレス。cloud-init のインターフェース特定にも使う"
  type        = string
  default     = "52:54:00:6c:3c:01"
}

variable "ip_address" {
  description = "VM の固定 IPv4 アドレス"
  type        = string
}

variable "ip_prefix" {
  description = "サブネットのプレフィックス長"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "デフォルトゲートウェイ"
  type        = string
}

variable "dns_servers" {
  description = "DNS サーバー"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# OS 初期設定
# ---------------------------------------------------------------------------
variable "fqdn" {
  description = "GitLab の FQDN（external_url と証明書の SAN に使う）"
  type        = string
}

variable "admin_user" {
  description = "cloud-init で作成する管理ユーザー（Ansible の接続ユーザー）"
  type        = string
  default     = "admin"
}

variable "ssh_public_key_path" {
  description = "管理ユーザーに登録する macOS 側の公開鍵"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "timezone" {
  description = "VM のタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

# ---------------------------------------------------------------------------
# Ansible 連携
# ---------------------------------------------------------------------------
variable "ansible_proxy_jump" {
  description = "Ansible から VM へ直接届かない場合（NAT 構成など）の踏み台。~/.ssh/config の Host 名を指定。空なら直接接続"
  type        = string
  default     = ""
}

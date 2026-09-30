variable "libvirt_uri" {
  description = "KVM ホストの libvirt 接続 URI。sshcmd は macOS の ~/.ssh/config を尊重する"
  type        = string
  # 例: qemu+sshcmd://kvm-host/system
}

variable "storage_pool" {
  description = "ディスクを配置する libvirt ストレージプール"
  type        = string
  default     = "default"
}

variable "vm_name" {
  description = "VM 名 (hostname にも使用)"
  type        = string
  default     = "coolify"
}

variable "vcpu" {
  description = "vCPU 数 (Coolify 公式最小: 2 core)"
  type        = number
  default     = 2
}

variable "memory_mib" {
  description = "メモリ MiB (Coolify 公式最小: 2 GB。ビルドを行うなら 4 GB 以上推奨)"
  type        = number
  default     = 4096
}

variable "disk_gib" {
  description = "ルートディスク容量 GiB (Coolify 公式最小: 10 GB 空き)"
  type        = number
  default     = 40
}

variable "rocky_image_url" {
  description = "Rocky Linux GenericCloud qcow2 の URL"
  type        = string
  default     = "https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
}

variable "bridge_name" {
  description = "LAN に接続された KVM ホスト側ブリッジ名"
  type        = string
  default     = "br0"
}

variable "nic_name" {
  description = "ゲスト内 NIC 名 (Rocky GenericCloud は net.ifnames=0 のため eth0)"
  type        = string
  default     = "eth0"
}

variable "vm_ip_cidr" {
  description = "VM の固定 IP (CIDR 表記)。例: 192.168.1.50/24"
  type        = string
}

variable "gateway" {
  description = "デフォルトゲートウェイ"
  type        = string
}

variable "dns_servers" {
  description = "DNS サーバー"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "admin_user" {
  description = "cloud-init で作成する管理ユーザー (Ansible の接続ユーザー)"
  type        = string
  default     = "rocky"
}

variable "ssh_public_key_path" {
  description = "admin_user に登録する macOS 側の公開鍵"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "timezone" {
  description = "ゲストのタイムゾーン"
  type        = string
  default     = "Asia/Tokyo"
}

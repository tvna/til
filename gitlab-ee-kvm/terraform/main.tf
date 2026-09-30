locals {
  hostname       = split(".", var.fqdn)[0]
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

# ---------------------------------------------------------------------------
# ディスク
# ---------------------------------------------------------------------------

# ベースイメージ。provider が macOS 側でダウンロードし、libvirt 経由でプールへ転送する。
resource "libvirt_volume" "base" {
  name = basename(var.base_image_url)
  pool = var.storage_pool

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = { url = var.base_image_url }
  }
}

# ルートディスク。ベースイメージを backing store にした CoW ディスク。
# 初回起動時に cloud-init (growpart) がパーティションを容量いっぱいまで拡張する。
resource "libvirt_volume" "root" {
  name     = "${var.vm_name}-root.qcow2"
  pool     = var.storage_pool
  capacity = var.vm_disk_gib * 1024 * 1024 * 1024

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }
}

# ---------------------------------------------------------------------------
# cloud-init
# ---------------------------------------------------------------------------
resource "libvirt_cloudinit_disk" "seed" {
  name = "${var.vm_name}-seed"

  meta_data = yamlencode({
    "instance-id"    = "${var.vm_name}-001"
    "local-hostname" = local.hostname
  })

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname       = local.hostname
    fqdn           = var.fqdn
    admin_user     = var.admin_user
    ssh_public_key = local.ssh_public_key
    timezone       = var.timezone
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    mac_address = var.mac_address
    ip_address  = var.ip_address
    ip_prefix   = var.ip_prefix
    gateway     = var.gateway
    dns_servers = var.dns_servers
  })
}

resource "libvirt_volume" "seed" {
  name = "${var.vm_name}-seed.iso"
  pool = var.storage_pool

  create = {
    content = { url = libvirt_cloudinit_disk.seed.path }
  }
}

# ---------------------------------------------------------------------------
# VM
# ---------------------------------------------------------------------------
resource "libvirt_domain" "gitlab" {
  name        = var.vm_name
  type        = "kvm"
  vcpu        = var.vm_vcpu
  memory      = var.vm_memory_mib
  memory_unit = "MiB"
  autostart   = true
  running     = true

  # Rocky Linux 10 は x86-64-v3 (AVX2 等) が必須。
  # 既定の CPU モデルだと v3 の命令が見えず起動できない場合があるため、ホスト CPU をそのまま渡す。
  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.root.pool
            volume = libvirt_volume.root.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = { type = "qcow2" }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.seed.pool
            volume = libvirt_volume.seed.name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      },
    ]

    interfaces = [
      {
        model = { type = "virtio" }
        mac   = { address = var.mac_address }
        source = {
          bridge  = var.network_mode == "bridge" ? { bridge = var.network_name } : null
          network = var.network_mode == "network" ? { network = var.network_name } : null
        }
      },
    ]

    # 緊急用コンソール。KVM ホストのループバックのみで待ち受けるため、SSH トンネル経由で使う。
    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      },
    ]
  }
}

# ---------------------------------------------------------------------------
# Ansible インベントリ生成
# ---------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    fqdn        = var.fqdn
    ip_address  = var.ip_address
    admin_user  = var.admin_user
    proxy_jump  = var.ansible_proxy_jump
    domain_name = libvirt_domain.gitlab.name
  })
}

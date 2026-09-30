locals {
  vm_ip          = split("/", var.vm_ip_cidr)[0]
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

# Rocky Linux 公式クラウドイメージ (macOS 側でダウンロードし libvirt へアップロードされる)
resource "libvirt_volume" "rocky_base" {
  name = "${var.vm_name}-rocky-base.qcow2"
  pool = var.storage_pool
  target = {
    format = { type = "qcow2" }
  }
  create = {
    content = { url = var.rocky_image_url }
  }
}

# ルートディスク (ベースイメージを backing store とする CoW ディスク)
resource "libvirt_volume" "root" {
  name     = "${var.vm_name}-root.qcow2"
  pool     = var.storage_pool
  capacity = var.disk_gib * 1024 * 1024 * 1024
  target = {
    format = { type = "qcow2" }
  }
  backing_store = {
    path   = libvirt_volume.rocky_base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  name = "${var.vm_name}-cloudinit"

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname       = var.vm_name
    admin_user     = var.admin_user
    ssh_public_key = local.ssh_public_key
    timezone       = var.timezone
  })

  meta_data = yamlencode({
    instance-id    = "${var.vm_name}-001"
    local-hostname = var.vm_name
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    nic_name    = var.nic_name
    vm_ip_cidr  = var.vm_ip_cidr
    gateway     = var.gateway
    dns_servers = var.dns_servers
  })
}

resource "libvirt_volume" "cloudinit" {
  name = "${var.vm_name}-cloudinit.iso"
  pool = var.storage_pool
  create = {
    content = { url = libvirt_cloudinit_disk.init.path }
  }
}

resource "libvirt_domain" "coolify" {
  name        = var.vm_name
  type        = "kvm"
  vcpu        = var.vcpu
  memory      = var.memory_mib
  memory_unit = "MiB"
  autostart   = true
  running     = true

  # Rocky 10 は x86-64-v3 必須。Rocky 9 でもホスト CPU をそのまま渡しておく
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
        target = { bus = "virtio", dev = "vda" }
        driver = { type = "qcow2" }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.cloudinit.pool
            volume = libvirt_volume.cloudinit.name
          }
        }
        target = { bus = "sata", dev = "sda" }
      },
    ]

    # LAN に直接参加させるためホストのブリッジへ接続
    interfaces = [
      {
        model = { type = "virtio" }
        source = {
          bridge = { bridge = var.bridge_name }
        }
      },
    ]

    # `virsh console` でシリアルコンソールに入れるようにする
    consoles = [
      {
        target = { type = "serial", port = 0 }
      },
    ]
  }
}

# Ansible 用インベントリを生成
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
  content         = <<-EOT
    [coolify_hosts]
    ${var.vm_name} ansible_host=${local.vm_ip} ansible_user=${var.admin_user}
  EOT
}

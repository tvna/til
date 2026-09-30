terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # v0.9 系でスキーマが libvirt XML 準拠に全面改訂されている。
    # 0.8 系以前のサンプルは流用できないため 0.9 系に固定する。
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.9"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

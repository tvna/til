output "vm_ip" {
  description = "Coolify VM の IP アドレス"
  value       = local.vm_ip
}

output "ssh_command" {
  description = "VM への SSH コマンド"
  value       = "ssh ${var.admin_user}@${local.vm_ip}"
}

output "coolify_url" {
  description = "Coolify ダッシュボード URL (Ansible 実行後に有効)"
  value       = "http://${local.vm_ip}:8000"
}

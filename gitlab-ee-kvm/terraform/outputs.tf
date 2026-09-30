output "gitlab_url" {
  description = "GitLab の URL"
  value       = "https://${var.fqdn}"
}

output "vm_ip_address" {
  description = "VM の IP アドレス"
  value       = var.ip_address
}

output "ssh_command" {
  description = "VM へのログインコマンド"
  value       = var.ansible_proxy_jump == "" ? "ssh ${var.admin_user}@${var.ip_address}" : "ssh -J ${var.ansible_proxy_jump} ${var.admin_user}@${var.ip_address}"
}

output "ansible_inventory" {
  description = "生成した Ansible インベントリ"
  value       = abspath(local_file.ansible_inventory.filename)
}

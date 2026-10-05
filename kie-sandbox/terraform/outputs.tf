output "vm_ip" {
  description = "KIE Sandbox VM の IP アドレス"
  value       = local.vm_ip
}

output "ssh_command" {
  description = "VM への SSH コマンド"
  value       = "ssh ${var.admin_user}@${local.vm_ip}"
}

output "kie_sandbox_url" {
  description = "KIE Sandbox の URL (Ansible 実行後に有効)"
  value       = "http://${local.vm_ip}:9090"
}

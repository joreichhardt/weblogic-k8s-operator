data "external" "traefik_nodeport" {
  program = ["bash", "-c", "port=$(kubectl get svc traefik -n traefik --context=${var.kube_context} -o jsonpath='{.spec.ports[?(@.name==\"websecure\")].nodePort}'); printf '{\"port\":\"%s\"}' \"$port\""]

  depends_on = [terraform_data.traefik]
}

locals {
  base_url = "https://${data.external.minikube_ip.result.ip}:${data.external.traefik_nodeport.result.port}"
}

output "admin_console" {
  value = "${local.base_url}/console"
}

output "remote_console" {
  value = "${local.base_url}/rconsole"
}

output "quickstart_app" {
  value = "${local.base_url}/quickstart"
}

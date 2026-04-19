# ── Minikube ───────────────────────────────────────────────────────────────────

resource "terraform_data" "minikube_start" {
  input = var.kube_context

  provisioner "local-exec" {
    command = "minikube start --profile=${self.input}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "minikube delete --profile=${self.input}"
  }
}

# ── Namespaces ────────────────────────────────────────────────────────────────

resource "terraform_data" "namespaces" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl create namespace ${var.operator_namespace} --dry-run=client -o yaml | kubectl apply -f -
      kubectl create namespace ${var.domain_namespace} --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }
  depends_on = [terraform_data.minikube_start]
}

# ── Helm: Sealed Secrets Controller ───────────────────────────────────────────

resource "terraform_data" "sealed_secrets" {
  provisioner "local-exec" {
    command = "helm list -n kube-system | grep -q sealed-secrets || helm upgrade --install sealed-secrets sealed-secrets --repo https://bitnami-labs.github.io/sealed-secrets --namespace kube-system --wait"
  }
  depends_on = [terraform_data.minikube_start]
}

# ── Helm: Traefik ──────────────────────────────────────────────────────────────

resource "terraform_data" "traefik" {
  provisioner "local-exec" {
    command = "helm list -n traefik | grep -q traefik || helm upgrade --install traefik traefik --repo https://traefik.github.io/charts --namespace traefik --create-namespace --wait"
  }
  depends_on = [terraform_data.minikube_start]
}

# ── Helm: WebLogic Kubernetes Operator ────────────────────────────────────────

resource "terraform_data" "weblogic_operator" {
  provisioner "local-exec" {
    command = "helm list -n ${var.operator_namespace} | grep -q weblogic-operator || helm upgrade --install weblogic-operator weblogic-operator --repo https://oracle.github.io/weblogic-kubernetes-operator/charts --version ${var.weblogic_operator_version} --namespace ${var.operator_namespace} --set 'domainNamespaces[0]=${var.domain_namespace}' --wait"
  }
  depends_on = [terraform_data.namespaces]
}

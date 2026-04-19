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

# ── Cluster-UID: ändert sich bei jedem minikube delete + start ─────────────────

data "external" "cluster_uid" {
  program = ["bash", "-c", "uid=$(kubectl get namespace kube-system --context=${var.kube_context} -o jsonpath='{.metadata.uid}'); printf '{\"uid\":\"%s\"}' \"$uid\""]

  depends_on = [terraform_data.minikube_start]
}

# ── Namespaces ────────────────────────────────────────────────────────────────

resource "terraform_data" "namespaces" {
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

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
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

  provisioner "local-exec" {
    command = "helm upgrade --install sealed-secrets sealed-secrets --repo https://bitnami-labs.github.io/sealed-secrets --namespace kube-system --wait"
  }
  depends_on = [terraform_data.minikube_start]
}

# ── Helm: Traefik ──────────────────────────────────────────────────────────────

resource "terraform_data" "traefik" {
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

  provisioner "local-exec" {
    command = "helm upgrade --install traefik traefik --repo https://traefik.github.io/charts --namespace traefik --create-namespace --set service.type=NodePort --wait --timeout 5m"
  }
  depends_on = [terraform_data.minikube_start]
}

# ── Helm: WebLogic Kubernetes Operator ────────────────────────────────────────

resource "terraform_data" "weblogic_operator" {
  triggers_replace = {
    cluster_uid = data.external.cluster_uid.result.uid
  }

  provisioner "local-exec" {
    command = "helm upgrade --install weblogic-operator weblogic-operator --repo https://oracle.github.io/weblogic-kubernetes-operator/charts --version ${var.weblogic_operator_version} --namespace ${var.operator_namespace} --set 'domainNamespaces[0]=${var.domain_namespace}' --wait"
  }
  depends_on = [terraform_data.namespaces]
}

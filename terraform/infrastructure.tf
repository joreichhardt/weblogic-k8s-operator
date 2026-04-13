# ── Namespaces ────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "operator" {
  metadata {
    name = var.operator_namespace
  }
}

resource "kubernetes_namespace" "domain" {
  metadata {
    name = var.domain_namespace
  }
}

# ── Helm: Sealed Secrets Controller ───────────────────────────────────────────

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  namespace  = "kube-system"
  wait       = true
}

# ── Helm: Traefik ──────────────────────────────────────────────────────────────

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = "kube-system"
  wait       = true

  set {
    name  = "ports.websecure.tls.enabled"
    value = "false"
  }

  set {
    name  = "ports.web.redirectTo.port"
    value = "websecure"
  }
}

# ── Helm: WebLogic Kubernetes Operator ────────────────────────────────────────

resource "helm_release" "weblogic_operator" {
  name       = "weblogic-operator"
  repository = "https://oracle.github.io/weblogic-kubernetes-operator/charts"
  chart      = "weblogic-operator"
  version    = var.weblogic_operator_version
  namespace  = var.operator_namespace
  wait       = true

  set {
    name  = "domainNamespaces[0]"
    value = var.domain_namespace
  }

  depends_on = [
    kubernetes_namespace.operator,
    kubernetes_namespace.domain,
  ]
}

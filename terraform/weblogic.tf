# ── OCR Pull Secret ───────────────────────────────────────────────────────────

resource "kubernetes_secret" "ocr_secret" {
  metadata {
    name      = "ocr-secret"
    namespace = var.domain_namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "container-registry.oracle.com" = {
          username = var.ocr_username
          password = var.ocr_password
          auth     = base64encode("${var.ocr_username}:${var.ocr_password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.domain]
}

# ── Sealed Secrets ────────────────────────────────────────────────────────────

resource "kubectl_manifest" "sealed_weblogic_credentials" {
  yaml_body = file("${path.module}/../secrets/sealed-weblogic-credentials.yaml")

  depends_on = [
    helm_release.sealed_secrets,
    kubernetes_namespace.domain,
  ]
}

resource "kubectl_manifest" "sealed_runtime_encryption_secret" {
  yaml_body = file("${path.module}/../secrets/sealed-runtime-encryption-secret.yaml")

  depends_on = [
    helm_release.sealed_secrets,
    kubernetes_namespace.domain,
  ]
}

# ── WebLogic Cluster & Domain ─────────────────────────────────────────────────

resource "kubectl_manifest" "cluster" {
  yaml_body = file("${path.module}/../cluster.yaml")

  depends_on = [
    helm_release.weblogic_operator,
    kubernetes_namespace.domain,
  ]
}

resource "kubectl_manifest" "domain" {
  yaml_body = file("${path.module}/../domain.yaml")

  depends_on = [
    kubectl_manifest.cluster,
    kubectl_manifest.sealed_weblogic_credentials,
    kubectl_manifest.sealed_runtime_encryption_secret,
    kubernetes_secret.ocr_secret,
  ]
}

# ── Traefik IngressRoutes ─────────────────────────────────────────────────────

data "kubectl_file_documents" "traefik_routes" {
  content = file("${path.module}/../traefik.yaml")
}

resource "kubectl_manifest" "traefik_routes" {
  for_each  = data.kubectl_file_documents.traefik_routes.manifests
  yaml_body = each.value

  depends_on = [
    helm_release.traefik,
    kubernetes_namespace.domain,
  ]
}

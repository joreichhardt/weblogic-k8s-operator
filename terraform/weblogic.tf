# ── Sealed Secrets ────────────────────────────────────────────────────────────

resource "kubectl_manifest" "sealed_weblogic_credentials" {
  yaml_body = file("${path.module}/../secrets/sealed-weblogic-credentials.yaml")

  depends_on = [
    terraform_data.sealed_secrets,
    terraform_data.namespaces,
  ]
}

resource "kubectl_manifest" "sealed_runtime_encryption_secret" {
  yaml_body = file("${path.module}/../secrets/sealed-runtime-encryption-secret.yaml")

  depends_on = [
    terraform_data.sealed_secrets,
    terraform_data.namespaces,
  ]
}

# ── WebLogic Cluster & Domain ─────────────────────────────────────────────────

resource "kubectl_manifest" "cluster" {
  yaml_body = file("${path.module}/../cluster.yaml")

  depends_on = [
    terraform_data.weblogic_operator,
    terraform_data.namespaces,
  ]
}

resource "kubectl_manifest" "domain" {
  yaml_body = templatefile("${path.module}/../domain.yaml", {
    aux_image_tag = var.aux_image_tag
  })

  depends_on = [
    kubectl_manifest.cluster,
    kubectl_manifest.sealed_weblogic_credentials,
    kubectl_manifest.sealed_runtime_encryption_secret,
    terraform_data.aux_image,
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
    terraform_data.traefik,
    terraform_data.namespaces,
  ]
}

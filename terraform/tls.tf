# ── Minikube IP ───────────────────────────────────────────────────────────────

data "external" "minikube_ip" {
  program = ["bash", "-c", "echo \"{\\\"ip\\\": \\\"$(minikube ip --profile=${var.kube_context})\\\"}\""]

  depends_on = [terraform_data.minikube_start]
}

# ── TLS: Self-signed CA ────────────────────────────────────────────────────────

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem   = tls_private_key.ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "WebLogic Local CA"
    organization = "Local Dev"
  }

  validity_period_hours = 87600 # 10 Jahre

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ── TLS: Server-Zertifikat ─────────────────────────────────────────────────────

resource "tls_private_key" "weblogic" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "weblogic" {
  private_key_pem = tls_private_key.weblogic.private_key_pem

  subject {
    common_name  = data.external.minikube_ip.result.ip
    organization = "Local Dev"
  }

  ip_addresses = [data.external.minikube_ip.result.ip]
}

resource "tls_locally_signed_cert" "weblogic" {
  cert_request_pem   = tls_cert_request.weblogic.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 87600

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── Kubernetes TLS Secret (im Traefik-Namespace) ──────────────────────────────

resource "kubernetes_secret" "weblogic_tls" {
  metadata {
    name      = "weblogic-tls"
    namespace = "traefik"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_locally_signed_cert.weblogic.cert_pem
    "tls.key" = tls_private_key.weblogic.private_key_pem
  }

  depends_on = [terraform_data.traefik]
}

# ── Traefik Default TLSStore ───────────────────────────────────────────────────

resource "kubectl_manifest" "tls_store" {
  yaml_body = <<-YAML
    apiVersion: traefik.io/v1alpha1
    kind: TLSStore
    metadata:
      name: default
      namespace: traefik
    spec:
      defaultCertificate:
        secretName: weblogic-tls
  YAML

  depends_on = [kubernetes_secret.weblogic_tls]
}

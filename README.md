# WebLogic K8s Operator on Minikube

WebLogic Server 15.1.1 auf Kubernetes (Minikube) mit dem WebLogic Kubernetes Operator, Traefik v3 als Ingress-Controller und Sealed Secrets für sichere Secret-Verwaltung.

## Architektur

```
Browser
  └── Traefik v3 (IngressRoute)
        ├── /console   → admin-server:7001  (WebLogic Remote Console)
        ├── /rconsole  → admin-server:7001  (WebLogic Remote Console WAR)
        └── /quickstart → cluster-1:8001   (Sample WAR App)

Namespace: weblogic-domain1-ns
  ├── Domain: sample-domain1  (Model-in-Image)
  │     ├── Admin Server  (admin-server)
  │     └── Managed Server (managed-server1, cluster-1)
  └── Secrets (Sealed Secrets)
        ├── sample-domain1-weblogic-credentials
        └── sample-domain1-runtime-encryption-secret
```

## Voraussetzungen

| Tool | Version |
|------|---------|
| Minikube | ≥ 1.32 |
| kubectl | ≥ 1.28 |
| Helm | ≥ 3.12 |
| kubeseal | ≥ 0.24 |
| Docker | ≥ 24 |
| WebLogic Image Tool (`imagetool`) | ≥ 1.12 |
| WebLogic Deploy Tooling (`weblogic-deploy`) | ≥ 4.x |

Zugang zum Oracle Container Registry (OCR) ist erforderlich für das WebLogic Base-Image.

## Setup

### 1. Minikube starten

```bash
minikube start --driver=kvm2 --cpus=4 --memory=8192
```

### 2. WebLogic Kubernetes Operator installieren

```bash
helm repo add weblogic-operator https://oracle.github.io/weblogic-kubernetes-operator/charts
helm repo update

kubectl create namespace weblogic-operator-ns
kubectl create namespace weblogic-domain1-ns

helm install weblogic-operator weblogic-operator/weblogic-operator \
  --namespace weblogic-operator-ns \
  --set "domainNamespaces={weblogic-domain1-ns}" \
  --wait
```

### 3. Traefik installieren

```bash
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik \
  --namespace kube-system \
  --set "ports.websecure.tls.enabled=false" \
  --set "ports.web.redirectTo.port=websecure" \
  --wait
```

### 4. Sealed Secrets Controller installieren

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system
```

### 5. OCR Secret erstellen

```bash
kubectl create secret docker-registry ocr-secret \
  --docker-server=container-registry.oracle.com \
  --docker-username=<your-oracle-sso-email> \
  --docker-password=<your-oracle-sso-password> \
  --namespace weblogic-domain1-ns
```

### 6. Sealed Secrets anwenden

```bash
kubectl apply -f secrets/sealed-weblogic-credentials.yaml
kubectl apply -f secrets/sealed-runtime-encryption-secret.yaml
```

> Die Sealed Secrets sind nur mit dem privaten Schlüssel des installierten Controllers entschlüsselbar. Für einen neuen Cluster müssen die Secrets neu versiegelt werden (siehe [Secrets neu erstellen](#secrets-neu-erstellen)).

### 7. Auxiliary Image bauen

```bash
cd quickstart

# Archive erstellen
cd models/archive
zip -r ../archive.zip wlsdeploy/
cd ../..

# Image bauen (imagetool muss konfiguriert sein)
imagetool create-aux-image \
  --tag quick-start-aux-image:v6 \
  --wdtModel models/model.yaml \
  --wdtVariables models/model.properties \
  --wdtArchive models/archive.zip \
  --wdtModelOnly

# Image in Minikube laden
minikube image load quick-start-aux-image:v6
```

### 8. Domain und Cluster deployen

```bash
kubectl apply -f cluster.yaml
kubectl apply -f domain.yaml
kubectl apply -f traefik.yaml
```

### 9. Status prüfen

```bash
kubectl get pods -n weblogic-domain1-ns
kubectl get domain sample-domain1 -n weblogic-domain1-ns
```

Beide Pods (`admin-server` und `sample-domain1-managed-server1`) sollten den Status `Running` haben.

## Zugriff

Minikube-IP ermitteln:
```bash
minikube ip
# Beispiel: 192.168.39.188
```

NodePort ermitteln:
```bash
kubectl get svc -n kube-system traefik
```

| Anwendung | URL |
|-----------|-----|
| WebLogic Remote Console | `http://<MINIKUBE_IP>:<NODEPORT>/rconsole` |
| Quickstart App | `http://<MINIKUBE_IP>:<NODEPORT>/quickstart` |

## Verzeichnisstruktur

```
.
├── domain.yaml                          # WebLogic Domain (Model-in-Image)
├── cluster.yaml                         # Cluster-Ressource (cluster-1)
├── traefik.yaml                         # Traefik IngressRoutes
├── secrets/
│   ├── sealed-weblogic-credentials.yaml # Admin-Credentials (verschlüsselt)
│   └── sealed-runtime-encryption-secret.yaml
└── quickstart/
    └── models/
        ├── model.yaml                   # WDT Domain-Modell
        ├── model.properties             # Konfigurationsvariablen
        └── archive/
            └── wlsdeploy/
                └── applications/
                    └── quickstart/      # Sample WAR (index.jsp + web.xml)
```

## Konfiguration

### Domain-Modell anpassen (`quickstart/models/model.yaml`)

Nach Änderungen am Modell muss das Auxiliary Image neu gebaut und die `introspectVersion` in `domain.yaml` erhöht werden:

```bash
# image neu bauen (v7 als Beispiel)
imagetool create-aux-image --tag quick-start-aux-image:v7 ...
minikube image load quick-start-aux-image:v7
```

`domain.yaml` aktualisieren:
```yaml
spec:
  configuration:
    model:
      auxiliaryImages:
        - image: "quick-start-aux-image:v7"
  introspectVersion: "7"
  restartVersion: "7"
```

```bash
kubectl apply -f domain.yaml
```

## Secrets neu erstellen

Wenn der Sealed Secrets Controller neu installiert wird (neuer öffentlicher Schlüssel), müssen die Secrets neu versiegelt werden:

```bash
# Weblogic Credentials
kubectl create secret generic sample-domain1-weblogic-credentials \
  --from-literal=username=weblogic \
  --from-literal=password=<PASSWORT> \
  --namespace weblogic-domain1-ns \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system -o yaml \
  > secrets/sealed-weblogic-credentials.yaml

# Runtime Encryption Secret
kubectl create secret generic sample-domain1-runtime-encryption-secret \
  --from-literal=password=<PASSWORT> \
  --namespace weblogic-domain1-ns \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system -o yaml \
  > secrets/sealed-runtime-encryption-secret.yaml
```

## Technologie-Stack

- **WebLogic Server** 15.1.1 (Jakarta EE 9.1, Servlet 5.0)
- **WebLogic Kubernetes Operator** v4.3.7
- **WebLogic Deploy Tooling (WDT)** — Model-in-Image
- **Traefik** v3 — Ingress Controller
- **Sealed Secrets** (Bitnami) — GitOps-sichere Secret-Verwaltung
- **Minikube** mit KVM2-Driver

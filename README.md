# WebLogic K8s Operator on Minikube

WebLogic Server 15.1.1 auf Kubernetes (Minikube) mit dem WebLogic Kubernetes Operator, Traefik v3 als Ingress-Controller und Sealed Secrets für sichere Secret-Verwaltung.

## Warum WebLogic auf Kubernetes?

Traditionell läuft WebLogic auf dedizierten VMs oder Bare-Metal-Servern. WebLogic selbst skaliert dabei gut — Dynamic Clusters, Session Replication und Work Manager Queues sind seit Langem eingebaut. Das eigentliche Problem war der Betrieb drumherum: Eine neue Managed-Server-Instanz bedeutete VM beantragen, OS installieren, WebLogic installieren, Cluster beitreten, manuell konfigurieren — Tage statt Minuten, fehleranfällig und schwer reproduzierbar. Kubernetes löst genau diesen operativen Aufwand:

### Betrieb und Verfügbarkeit

- **Automatischer Neustart:** Kubernetes erkennt abgestürzte Pods und startet sie selbsttätig neu — ohne manuellen Eingriff.
- **Rolling Updates ohne Downtime:** Neue Domain-Versionen werden rolling ausgerollt; der Operator koordiniert die Reihenfolge (Admin-Server zuerst, dann Managed Server).
- **Selbstheilung:** Fällt ein Node aus, verschiebt Kubernetes die Pods automatisch auf gesunde Nodes.

### Skalierung

- **Horizontal skalierbar:** Managed Server lassen sich durch eine einzige Änderung an `replicas` in `cluster.yaml` hoch- oder runterskalieren. Der Operator startet die neuen Instanzen, meldet sie am Cluster an und konfiguriert sie — ohne manuellen Eingriff, in Minuten statt Tagen.
- **Ressourcenlimits:** CPU und Memory werden per Pod definiert, sodass einzelne Domains sich nicht gegenseitig stören.

### Deployment und Betrieb als Code

- **GitOps-fähig:** Die gesamte Domain-Konfiguration (Modell, Secrets, Ingress) liegt als YAML im Repository. Änderungen sind nachvollziehbar, reproduzierbar und peer-reviewbar.
- **Model-in-Image:** Das WDT-Modell beschreibt die Domain deklarativ — kein Clicken in Admin-Konsolen, kein Drift zwischen Umgebungen.
- **Sealed Secrets:** Verschlüsselte Secrets können sicher in Git versioniert werden, ohne Credentials preiszugeben.

### Isolation und Mandantenfähigkeit

- **Namespace-Isolation:** Jede Domain läuft in einem eigenen Namespace mit eigenen Credentials und Netzwerkregeln — mehrere Teams oder Applikationen auf demselben Cluster ohne gegenseitige Beeinflussung.
- **Keine gemeinsame Middleware:** Kein geteilter Application-Server für mehrere Apps, der bei einem Fehler alles mitreißt.

### Bare-Metal-Betrieb

Besonders auf Bare Metal entfaltet Kubernetes seinen vollen Vorteil: Klassische Setups benötigen Hypervisor + VM + Betriebssystem + Application-Server — jede Schicht kostet Latenz, RAM und Verwaltungsaufwand. Auf Bare Metal entfällt die Virtualisierungsschicht vollständig.

- **Direkte Hardware-Nutzung:** Kein Hypervisor-Overhead, keine NUMA-Probleme durch VM-Boundaries, voller Zugriff auf CPU-Features und Speicherbandbreite.
- **Geringere Latenz:** Netzwerk-I/O und Speicherzugriff laufen ohne Virtualisierungs-Indirektion — relevant für transaktionsintensive WebLogic-Workloads.
- **Weniger bewegliche Teile:** Statt VM-Images, Snapshots und Hypervisor-Updates nur noch Container-Images und Kubernetes — der Betrieb wird schlanker und planbarer.
- **Ressourceneffizienz:** RAM und CPU, die sonst dem Hypervisor gehören, stehen den WebLogic-Domains direkt zur Verfügung.

### Portabilität

- **Läuft überall:** Minikube lokal, AKS, EKS, OKE oder On-Premises — das gleiche YAML, die gleiche Toolchain.
- **Kein Vendor-Lock-in auf Infrastruktur-Ebene:** Der Operator abstrahiert den Betrieb von der darunterliegenden Plattform.

---

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

## Deployment mit Terraform

Alternativ zum manuellen Setup kann die gesamte Infrastruktur mit Terraform aufgesetzt werden. Terraform übernimmt dabei Minikube, Namespaces, Helm-Releases und Kubernetes-Ressourcen — das Bauen des Auxiliary Image bleibt ein separater Build-Schritt.

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars mit OCR-Credentials befüllen (wird nicht eingecheckt)

terraform init
make apply    # startet Minikube, dann terraform apply
```

Teardown:

```bash
make destroy  # terraform destroy + minikube delete
```

Das direkte `terraform apply` / `terraform plan` schlägt fehl, wenn Minikube noch nicht läuft, weil die Kubernetes-Provider beim Plan bereits eine laufende API erwarten. Das Makefile startet Minikube vorher.

**Was Terraform deployt:**

| Ressource | Wie |
|-----------|-----|
| Minikube starten / beim Destroy löschen | `local-exec` |
| Namespaces (`weblogic-operator-ns`, `weblogic-domain1-ns`) | `local-exec` / kubectl |
| Sealed Secrets Controller | Helm |
| Traefik v3 | Helm |
| WebLogic Kubernetes Operator | Helm |
| OCR Pull Secret | kubernetes-Provider |
| Sealed Secrets (Credentials) | kubectl-Provider |
| Domain, Cluster | kubectl-Provider |
| Traefik IngressRoutes | kubectl-Provider |

**Was außerhalb von Terraform bleibt:**

- Auxiliary Image bauen (`imagetool`) — gehört in eine Build-Pipeline
- Sealed Secrets neu versiegeln (`kubeseal`) — einmaliger CLI-Schritt, Output landet als YAML im Repo

> `terraform.tfvars` enthält OCR-Credentials und darf nicht eingecheckt werden — ist bereits in `.gitignore` abgedeckt durch `secrets/*`. Alternativ Umgebungsvariablen verwenden: `TF_VAR_ocr_username`, `TF_VAR_ocr_password`.

---

## Setup (manuell)

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
eval $(minikube docker-env)
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) \
imagetool createAuxImage \
  --tag quick-start-aux-image:v7 \
  --wdtModel models/model.yaml \
  --wdtVariables models/model.properties \
  --wdtArchive models/archive.zip

# Image landet direkt in Minikubes Docker-Daemon (kein separates image load nötig)
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
kubectl get svc -n traefik traefik
```

| Anwendung | URL |
|-----------|-----|
| WebLogic Admin Console | `https://<MINIKUBE_IP>:<HTTPS_NODEPORT>/console` |
| WebLogic Remote Console | `https://<MINIKUBE_IP>:<HTTPS_NODEPORT>/rconsole` |
| Quickstart App | `https://<MINIKUBE_IP>:<HTTPS_NODEPORT>/quickstart` |

> Der HTTPS-NodePort (443) ist typischerweise `31320`. Das self-signed Zertifikat wird von Terraform automatisch generiert — der Browser zeigt beim ersten Aufruf eine Warnung.

## Verzeichnisstruktur

```
.
├── domain.yaml                          # WebLogic Domain (Model-in-Image)
├── cluster.yaml                         # Cluster-Ressource (cluster-1)
├── traefik.yaml                         # Traefik IngressRoutes
├── secrets/
│   ├── sealed-weblogic-credentials.yaml # Admin-Credentials (verschlüsselt)
│   └── sealed-runtime-encryption-secret.yaml
├── quickstart/
│   └── models/
│       ├── model.yaml                   # WDT Domain-Modell
│       ├── model.properties             # Konfigurationsvariablen
│       └── archive/
│           └── wlsdeploy/
│               └── applications/
│                   └── quickstart/      # Sample WAR (index.jsp + web.xml)
└── terraform/
    ├── Makefile                         # make apply / make destroy
    ├── main.tf                          # Provider-Konfiguration
    ├── infrastructure.tf                # Minikube, Namespaces, Helm-Releases
    ├── weblogic.tf                      # Secrets, Domain, Cluster, Ingress
    ├── variables.tf
    └── terraform.tfvars.example
```

## Konfiguration

### Domain-Modell anpassen (`quickstart/models/model.yaml`)

Nach Änderungen am Modell muss das Auxiliary Image neu gebaut und die `introspectVersion` in `domain.yaml` erhöht werden:

```bash
# image neu bauen (v7 als Beispiel)
eval $(minikube docker-env)
JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) \
imagetool createAuxImage --tag quick-start-aux-image:v7 \
  --wdtModel models/model.yaml \
  --wdtVariables models/model.properties \
  --wdtArchive models/archive.zip
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

> **Normalerweise nicht nötig:** `make apply` sichert den Sealed-Secrets-Controller-Key nach `~/.sealed-secrets-key.yaml` und stellt ihn bei jedem neuen Cluster automatisch wieder her. Die Secrets im Repo bleiben dauerhaft gültig.

Nur nötig wenn `~/.sealed-secrets-key.yaml` verloren gegangen ist (neuer Rechner, etc.):

```bash
# Weblogic Credentials
kubectl create secret generic sample-domain1-weblogic-credentials \
  --from-literal=username=weblogic \
  --from-literal=password=<PASSWORT> \
  --namespace weblogic-domain1-ns \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system --controller-name sealed-secrets -o yaml \
  > secrets/sealed-weblogic-credentials.yaml

# Runtime Encryption Secret
kubectl create secret generic sample-domain1-runtime-encryption-secret \
  --from-literal=password=<PASSWORT> \
  --namespace weblogic-domain1-ns \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system --controller-name sealed-secrets -o yaml \
  > secrets/sealed-runtime-encryption-secret.yaml

kubectl apply -f secrets/sealed-weblogic-credentials.yaml
kubectl apply -f secrets/sealed-runtime-encryption-secret.yaml
git add secrets/ && git commit -m "Re-seal secrets"
```

## Neue App in eigener Domain deployen

Jede Domain läuft vollständig isoliert in einem eigenen Kubernetes-Namespace mit eigenem Admin-Server, eigenen Managed Servern und eigenen Secrets. Domains teilen sich lediglich den WebLogic Kubernetes Operator und den Ingress-Controller.

### Überblick: Was pro Domain erstellt werden muss

```
myapp-ns/                          ← eigener Namespace
  ├── Secrets
  │     ├── myapp-weblogic-credentials          (versiegelt)
  │     └── myapp-runtime-encryption-secret     (versiegelt)
  ├── ocr-secret                   ← Pull-Secret für OCR
  ├── cluster.yaml                 ← Cluster-Ressource
  ├── domain.yaml                  ← Domain-Definition
  └── traefik.yaml                 ← IngressRoutes für diese Domain
myapp-aux-image:v1                 ← eigenes Auxiliary Image mit WDT-Modell + WAR
```

### Schritt 1: Namespace anlegen und Operator informieren

```bash
kubectl create namespace myapp-ns

# Operator so updaten, dass er den neuen Namespace überwacht
helm upgrade weblogic-operator weblogic-operator/weblogic-operator \
  --namespace weblogic-operator-ns \
  --set "domainNamespaces={weblogic-domain1-ns,myapp-ns}" \
  --reuse-values \
  --wait
```

### Schritt 2: Secrets erstellen und versiegeln

```bash
# Admin-Credentials
kubectl create secret generic myapp-weblogic-credentials \
  --from-literal=username=weblogic \
  --from-literal=password=<SICHERES_PASSWORT> \
  --namespace myapp-ns \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system -o yaml \
  > secrets/sealed-myapp-weblogic-credentials.yaml

# Runtime Encryption Secret (beliebiges starkes Passwort)
kubectl create secret generic myapp-runtime-encryption-secret \
  --from-literal=password=<ZUFALLS_PASSWORT> \
  --namespace myapp-ns \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system -o yaml \
  > secrets/sealed-myapp-runtime-encryption-secret.yaml

# OCR Pull-Secret (einmalig pro Namespace)
kubectl create secret docker-registry ocr-secret \
  --docker-server=container-registry.oracle.com \
  --docker-username=<ORACLE_EMAIL> \
  --docker-password=<ORACLE_PASSWORT> \
  --namespace myapp-ns

kubectl apply -f secrets/sealed-myapp-weblogic-credentials.yaml
kubectl apply -f secrets/sealed-myapp-runtime-encryption-secret.yaml
```

### Schritt 3: WDT-Modell und WAR vorbereiten

Verzeichnisstruktur für die neue App (analog zu `quickstart/`):

```
myapp/
└── models/
    ├── model.yaml          ← WDT Domain-Modell
    ├── model.properties    ← Port-Variablen etc.
    └── archive/
        └── wlsdeploy/
            └── applications/
                └── myapp/
                    ├── WEB-INF/web.xml
                    └── index.jsp   (oder fertiges .war)
```

**`myapp/models/model.yaml`** (Minimalbeispiel):

```yaml
domainInfo:
    AdminUserName: '@@SECRET:__weblogic-credentials__:username@@'
    AdminPassword: '@@SECRET:__weblogic-credentials__:password@@'
    ServerStartMode: dev
topology:
    Name: myapp
    AdminServerName: admin-server
    Cluster:
        cluster-1:
            DynamicServers:
                ServerNamePrefix: managed-server
                CalculatedListenPorts: false
                MaximumDynamicServerCount: 1
                ServerTemplate: server-template_1
                DynamicClusterSize: 1
    Server:
        admin-server: {}
    ServerTemplate:
        server-template_1:
            ListenPort: '@@PROP:ServerTemp.server-template_1.ListenPort@@'
            Cluster: cluster-1
appDeployments:
    Application:
        myapp:
            SourcePath: wlsdeploy/applications/myapp
            ModuleType: war
            Target: cluster-1
```

**`myapp/models/model.properties`**:

```properties
ServerTemp.server-template_1.ListenPort=8001
ServerTemp.server-template_1.SSL.ListenPort=8100
```

> **Jakarta EE Hinweis:** `web.xml` muss das Jakarta EE 9.1 Schema verwenden (Servlet 5.0), keine DTD.
> Imports in JSPs: `jakarta.servlet.*` statt `javax.servlet.*`.

### Schritt 4: Auxiliary Image bauen

```bash
cd myapp/models/archive
zip -r ../archive.zip wlsdeploy/
cd ../..

imagetool create-aux-image \
  --tag myapp-aux-image:v1 \
  --wdtModel models/model.yaml \
  --wdtVariables models/model.properties \
  --wdtArchive models/archive.zip \
  --wdtModelOnly

minikube image load myapp-aux-image:v1
```

### Schritt 5: Cluster-Ressource (`myapp/cluster.yaml`)

```yaml
apiVersion: weblogic.oracle/v1
kind: Cluster
metadata:
  name: myapp-cluster-1
  namespace: myapp-ns
  labels:
    weblogic.domainUID: myapp
spec:
  clusterName: cluster-1
  replicas: 1
```

### Schritt 6: Domain (`myapp/domain.yaml`)

```yaml
apiVersion: weblogic.oracle/v9
kind: Domain
metadata:
  name: myapp
  namespace: myapp-ns
  labels:
    weblogic.domainUID: myapp
spec:
  domainUID: myapp
  configuration:
    model:
      auxiliaryImages:
        - image: "myapp-aux-image:v1"
          imagePullPolicy: IfNotPresent
      runtimeEncryptionSecret: myapp-runtime-encryption-secret
  domainHomeSourceType: FromModel
  domainHome: /u01/domains/myapp
  image: container-registry.oracle.com/middleware/weblogic:15.1.1.0-generic-jdk17-ol8
  imagePullPolicy: IfNotPresent
  imagePullSecrets:
    - name: ocr-secret
  webLogicCredentialsSecret:
    name: myapp-weblogic-credentials
  includeServerOutInPodLog: true
  serverStartPolicy: IfNeeded
  serverPod:
    env:
      - name: JAVA_OPTIONS
        value: "-Dweblogic.StdoutDebugEnabled=false"
      - name: USER_MEM_ARGS
        value: "-Djava.security.egd=file:/dev/./urandom -Xms128m -Xmx256m"
    resources:
      requests:
        cpu: "250m"
        memory: "512Mi"
  replicas: 1
  clusters:
    - name: myapp-cluster-1
  restartVersion: "1"
  introspectVersion: "1"
```

### Schritt 7: Ingress-Routen (`myapp/traefik.yaml`)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp-route
  namespace: myapp-ns
spec:
  entryPoints:
    - websecure
  routes:
    - match: PathPrefix(`/myapp`)
      kind: Rule
      services:
        - name: myapp-cluster-cluster-1
          port: 8001
```

> Der Service-Name folgt dem Muster `<domainUID>-cluster-<clusterName>`.
> Der Operator erstellt ihn automatisch, sobald die Domain läuft.

### Schritt 8: Alles deployen

```bash
kubectl apply -f myapp/cluster.yaml
kubectl apply -f myapp/domain.yaml
kubectl apply -f myapp/traefik.yaml
```

### Status prüfen

```bash
kubectl get pods -n myapp-ns
kubectl get domain myapp -n myapp-ns
```

### Isolation zwischen Domains

| Aspekt | Verhalten |
|--------|-----------|
| Namespace | vollständig getrennt |
| Admin-Server | jede Domain hat einen eigenen |
| Secrets / Credentials | getrennt, kein Zugriff über Domains |
| Netzwerk | Pods können sich per Service-DNS erreichen, aber die Apps laufen isoliert |
| Shared | WebLogic Kubernetes Operator, Traefik, Sealed Secrets Controller, OCR Base-Image |

---

## Technologie-Stack

- **WebLogic Server** 15.1.1 (Jakarta EE 9.1, Servlet 5.0)
- **WebLogic Kubernetes Operator** v4.3.7
- **WebLogic Deploy Tooling (WDT)** — Model-in-Image
- **Traefik** v3 — Ingress Controller
- **Sealed Secrets** (Bitnami) — GitOps-sichere Secret-Verwaltung
- **Minikube** mit KVM2-Driver

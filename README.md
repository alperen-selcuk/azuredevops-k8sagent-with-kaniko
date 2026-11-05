# azuredevops-k8sagent-with-kaniko

Kubernetes üzerinde çalışan, Azure DevOps'a otomatik kayıt olan self-hosted agent.

- **Kaniko** ile Docker build alır ve push eder (Docker daemon gerekmez)
- **kubectl** ve **helm** içerir, pod içinden ServiceAccount ile cluster'a deploy edebilir
- Ayrıca `az cli`, `powershell`, `git`, `jq` hazır gelir

## Agent image içeriği

Base: `mcr.microsoft.com/dotnet/sdk:<DOTNET_SDK_VERSION>-jammy` (Ubuntu 22.04)

| Araç | Sürüm | Build-arg | Not |
|---|---|---|---|
| .NET SDK | 8.0 | `DOTNET_SDK_VERSION` | Başka sürümler için pipeline'da `UseDotNet@2` |
| Node.js + npm + corepack | 20 | `NODE_VERSION` | Next.js / Node projeleri |
| JDK | 17 | - | `JAVA_HOME=/usr/lib/jvm/default-java`, SonarQube scanner için de gerekli |
| Maven | 3.9 | `MAVEN_VERSION` | `MAVEN_HOME=/usr/share/maven` |
| kubectl | latest stable | `KUBECTL_VERSION` | Pinlemek için `v1.x.y` |
| helm | latest | `HELM_VERSION` | Pinlemek için `v3.x.y` |
| Kaniko | latest | `KANIKO_VERSION` | Pinlemek için `v1.x.y` |
| Azure Pipelines agent | latest | `RUNNER_VERSION` | Çalışma anında indirilir |
| `az cli`, `powershell`, `git`, `jq`, `curl`, `unzip` | - | - | |
| `build-essential`, `python3` | - | - | `node-gyp` gerektiren npm paketleri için |

`dotnet-coverage` gibi global dotnet tool'lar için `~/.dotnet/tools` PATH'tedir. Agent açılışta `java`, `node`, `npm`, `maven`, `dotnet` capability'lerini otomatik kaydeder (task demand'leri için).

## Kurulum

### 1. Agent image'ını build et ve push et

Deployment bu image'ı çekeceği için ilk adım bu.

```bash
docker build -t yourregistry/yourimage:<tag> .
docker push yourregistry/yourimage:<tag>
```

Arm64 için: `--build-arg K8S_ARCH=arm64` ve `start.sh` içindeki `TARGETARCH=linux-arm64`.

Sürümler opsiyonel build-arg'larla pinlenir; verilmezse hepsi **latest** gelir:

```bash
docker build \
  --build-arg RUNNER_VERSION=4.x.y \
  --build-arg KUBECTL_VERSION=v1.x.y \
  --build-arg KANIKO_VERSION=v1.x.y \
  --build-arg HELM_VERSION=v3.x.y \
  -t yourregistry/yourimage:<tag> .
```

Sonra [kubernetes/deployment.yaml](kubernetes/deployment.yaml) içindeki `image` alanını güncelle:

```yaml
image: yourregistry/yourimage:<tag>
```

Registry private ise cluster'ın image çekebilmesi için `imagePullSecrets` de gerekir.

### 2. Azure DevOps hazırlığı

- Bir **Agent Pool** oluştur (Organization Settings → Agent pools).
- **PAT** üret. Yetki: `Agent Pools (Read & manage)`.

### 3. Namespace ve Secret

```bash
kubectl create namespace azagent
./kubernetes/secret-creater.sh
```

Script sırasıyla Azure DevOps URL'ini (`https://dev.azure.com/<org>`), PAT'i, pool adını ve namespace'i (`azagent`) sorar.

### 4. RBAC ve Deployment

```bash
kubectl apply -f kubernetes/rbac.yaml
kubectl apply -f kubernetes/deployment.yaml
```

Birkaç dakika içinde agent'lar pool'da **Online** görünür.

> `rbac.yaml` agent'a tüm namespace'lerde `edit` yetkisi verir. Daha dar yetki için dosyadaki ClusterRoleBinding'i RoleBinding'e çevir.

### 5. (Opsiyonel) Helm repo

Pod her başladığında / restart olduğunda `HELM_REPO_NAME` ve `HELM_REPO_URL` env'leri varsa `helm repo add` + `helm repo update` çalışır. Env yoksa hiçbir şey yapılmaz.

| Env | Zorunlu | Açıklama |
|---|---|---|
| `HELM_REPO_NAME` | evet | Repo adı (örn. `chartmuseum`) |
| `HELM_REPO_URL` | evet | Repo URL'i |
| `HELM_REPO_USERNAME` | hayır | Auth açıksa |
| `HELM_REPO_PASSWORD` | hayır | Auth açıksa (Secret'tan ver) |

## Pipeline'da kullanım

```yaml
pool:
  name: <pool-adı>

steps:
# Kaniko ile build + push
- script: |
    executor \
      --context $(Build.SourcesDirectory) \
      --dockerfile $(Build.SourcesDirectory)/Dockerfile \
      --destination <registry>/<image>:$(Build.BuildId)
  displayName: Build & push

# Cluster'a deploy
- script: |
    helm upgrade --install myapp ./chart -n myapp --set image.tag=$(Build.BuildId)
  displayName: Deploy
```

Kaniko'nun registry'ye push edebilmesi için `/kaniko/.docker/config.json` içinde credential olmalı. Şablon: [docker-config.json](docker-config.json).

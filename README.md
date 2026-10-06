# azuredevops-k8sagent-with-kaniko

Kubernetes üzerinde çalışan, Azure DevOps'a otomatik kayıt olan self-hosted agent.

- **Kaniko** ile Docker build alır ve push eder (Docker daemon gerekmez)
- **kubectl** ve **helm** içerir, pod içinden ServiceAccount ile cluster'a deploy edebilir
- Ayrıca `az cli`, `powershell`, `git`, `jq` hazır gelir

## Kurulum

### 1. Azure DevOps hazırlığı

- Bir **Agent Pool** oluştur (Organization Settings → Agent pools).
- **PAT** üret. Yetki: `Agent Pools (Read & manage)`.

### 2. Namespace ve Secret

```bash
kubectl create namespace azagent
./kubernetes/secret-creater.sh
```

Script sırasıyla Azure DevOps URL'ini (`https://dev.azure.com/<org>`), PAT'i, pool adını ve namespace'i (`azagent`) sorar.

### 3. RBAC ve Deployment

```bash
kubectl apply -f kubernetes/rbac.yaml
kubectl apply -f kubernetes/deployment.yaml
```

Birkaç dakika içinde agent'lar pool'da **Online** görünür.

> `rbac.yaml` agent'a tüm namespace'lerde `edit` yetkisi verir. Daha dar yetki için dosyadaki ClusterRoleBinding'i RoleBinding'e çevir.

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

Kaniko'nun registry'ye push edebilmesi için `/kaniko/.docker/config.json` içinde credential olmalı. Şablon: [docker-config.json](docker-config.json). Bunu bir Secret'tan mount edebilirsin.

## Image'ı kendin build etmek

```bash
docker build -t yourregistry/yourimage:<tag> .
docker push yourregistry/yourimage:<tag>
```

Arm64 için: `--build-arg K8S_ARCH=arm64` ve `start.sh` içindeki `TARGETARCH=linux-arm64`.

Sonra [kubernetes/deployment.yaml](kubernetes/deployment.yaml) içindeki `image` alanını kendi image'ınla güncelle:

```yaml
image: yourregistry/yourimage:<tag>
```

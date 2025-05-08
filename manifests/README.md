## 一、目录结构说明
```bash
manifests/
├── base/          # 通用基础配置（所有环境共享）
├── overlays/           # 环境差异化配置（overlay 层）
│   ├── dev/       # 开发环境配置
│   └── prod/      # 生产环境配置
├── argo.yaml       # ArgoCD 控制平面部署（可选，已部署集群可忽略）
└── argocd-application.yaml  # ArgoCD Application 配置（指向环境目录）
```
## 二、Kustomize 部署命令
### 1. 开发环境部署（推荐本地测试）
### 步骤 1：生成开发环境清单
```bash
# 单个文件校验
kubectl apply --dry-run=client -f ./manifests/overlays/dev/namespace.yaml # kubectl 老版本

# Kustomize 构建校验（无实际部署）
kustomize build manifests/overlays/dev/ | kubectl apply --dry-run=client -f -

```
```bash
kustomize build manifests/overlays/dev/ > dev-manifest.yaml
```
### 步骤 2：应用到 Kubernetes 集群
```bash
kubectl apply -f dev-manifest.yaml
### 或直接通过 Kustomize 目录部署（推荐）
kubectl apply -k manifests/overlays/dev/
```
### 步骤 3：验证部署状态
```bash
kubectl get all -n laravel  # 检查 Pod/Deployment/Service 状态
kubectl logs <pod-name> -n laravel  # 查看应用日志
```
### 2. 生产环境部署（通过 ArgoCD 自动化）
### 步骤 1：生成生产环境清单（可选，手动验证）
```bash
kustomize build manifests/overlays/prod/ > prod-manifest.yaml
```
### 步骤 2：应用基础命名空间（首次部署）
```bash
kubectl apply -f manifests/base/namespace.yaml  # 创建 laravel 命名空间
```

### 敏感信息处理
```bash
# 交互式生成 Secret（推荐）
kubectl create secret generic laravel-app-secret \
  --from-literal=DB_PASSWORD=your-dev-password \
  --from-literal=REDIS_PASSWORD=your-dev-redis-password \
  -n laravel \
  -o yaml > manifests/overlays/dev/secret-env.yaml

# 或手动编码（base64）
echo -n "your-dev-password" | base64  # 生成密码的 base64 编码，写入 secret-env.yaml 的 data 字段
```
```bash
# 1. 执行以下命令生成真实的 .dockerconfigjson 编码值（替换 <> 内的参数）：
kubectl create secret docker-registry secret-acr \
  --docker-server=https://registry.cn-hangzhou.aliyuncs.com \
  --docker-username=1768177868@qq.com \
  --docker-password=<你的ACR密码> \
  -n laravel \
  --dry-run=client -o yaml | grep '.dockerconfigjson' | awk '{print $2}'

# 2. 将命令输出的字符串替换到secret-acr.yaml .dockerconfigjson 字段
```

### Git提交与镜像版本管理
```bash
# 提交代码并打标签
git commit -a -m "feat: tag 1.0.37"
# 创建新标签
git tag 1.0.37
# 仅推送新标签
# git push origin master --tags
git push origin 1.0.37
```
### CI/CD流程示例（GitHub Actions） 创建 .github/workflows/deploy-prod.yml
```yaml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v3

    - name: Extract semantic version
      id: tag
      run: |
        FULL_TAG=${GITHUB_REF#refs/tags/}
        SEMVER=$(echo "$FULL_TAG" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
        echo "SEMVER=$SEMVER" >> $GITHUB_ENV


    # 新增镜像构建步骤
    - name: Build and Push Docker Image
      env:
        REGISTRY: registry.cn-hangzhou.aliyuncs.com/xuancheng/laravel-app
      run: |
        docker build -t $REGISTRY:${{ env.SEMVER }} .
        echo ${{ secrets.ACR_PASSWORD }} | docker login -u 1768177868@qq.com --password-stdin registry.cn-hangzhou.aliyuncs.com
        docker push $REGISTRY:${{ env.SEMVER }}
    

    - name: Update Kustomize
      run: |
        sed -i "s/newTag:.*/newTag: ${{ env.SEMVER }}/" manifests/overlays/prod/kustomization.yaml

    - name: Commit changes
      run: |
        git config --global user.name "GitHub Actions"
        git config --global user.email "actions@github.com"
        git add manifests/overlays/prod/kustomization.yaml
        git commit -m "CI: Update image tag to ${{ env.SEMVER }}"
        git push origin main

    - name: Trigger ArgoCD Sync
      uses: steebchen/kubectl@v2.0
      with:
        config: ${{ secrets.KUBECONFIG_PROD }}
        command: |
          argocd app sync laravel-prod
          argocd app wait laravel-prod
```
### 验证配置
```bash
kubectl kustomize manifests/overlays/prod/  # 预览生成的配置
kubectl apply -k manifests/overlays/prod/   # 应用配置到集群
```
```bash
1. 自动触发 GitHub Actions 将：
- 提取语义化版本号（如 v1.3.1）
- 更新 kustomization.yaml
- 提交版本变更
- 触发 ArgoCD 同步
2. ArgoCD 行为
- 检测到仓库变更
- 拉取最新配置
- 应用更新到 Kubernetes 集群
```

### ArgoCD 添加仓库凭据
```bash
argocd repo add https://gitee.com/wangxuancheng/laravel-k3s-cluster.git \
  --username <gitee用户名> \
  --password <gitee密码> \
  --insecure-skip-server-verification

# 1. 仓库认证配置
# 2. 同步策略优化 syncOptions 配置项说明：
# - CreateNamespace=true ：自动创建目标命名空间
# - ApplyOutOfSyncOnly=true ：仅同步差异部分
# 3. 镜像更新策略 生产环境使用 targetRevision: HEAD 实现持续部署，开发环境使用固定分支 ( main ) 保持稳定

```

```bash
# 查看同步状态
argocd app get laravel-prod

# 手动触发同步
argocd app sync laravel-prod

# 查看资源树
argocd app resources laravel-prod

# 检查实际镜像版本
kubectl get deploy -n laravel-prod -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'
```

### 三、Drone部署流程 CI https://docs.drone.io/server/provider/gitee/
```bash
# gitee设置第三方应用，主页 http://43.167.238.150:8082
# gitee设置第三方应用，回调地址 http://43.167.238.150:8082/login
mkdir -p ./drone-data

vim drone-server.yml
```
```yaml
version: "3"
services:
  drone-server:
    image: drone/drone:latest
    container_name: drone-server
    ports:
      - "8082:80"       # Web 界面端口
      # - "443:443"       # HTTPS 端口（可选，建议生产环境启用）
    volumes:
      - ./drone-data:/data  # 持久化存储配置和日志
    environment:
      - DRONE_RPC_SECRET=5d01c09f2ba9ad28a15148d4ce1de86c         # openssl rand -hex 16
      # - DRONE_GITEA_SERVER=http://your-gitea-domain.com:3000    # 私有 Gitea 地址（含端口）
      # - DRONE_GITHUB_CLIENT_ID=your_github_client_id            # GitHub Client ID
      # - DRONE_GITHUB_CLIENT_SECRET=your_github_client_secret    # GitHub Client Secret
      - DRONE_GITEE_CLIENT_ID=your_gitee_client_id                # Gitee 客户端 ID
      - DRONE_GITEE_CLIENT_SECRET=your_gitee_client_secret        # Gitee 客户端密钥
      # - DRONE_GITLAB_CLIENT_ID=your_gitlab_client_id            # GitLab 客户端 ID
      # - DRONE_GITLAB_CLIENT_SECRET=your_gitlab_client_secret    # GitLab 客户端密钥
      # - DRONE_GITEA_CLIENT_ID=your_gitea_client_id              # Gitea 客户端 ID
      # - DRONE_GITEA_CLIENT_SECRET=your_gitea_client_secret      # Gitea 客户端密钥
      - DRONE_RUNNER_CAPACITY=20                            # 最大并发构建数
      - DRONE_SERVER_HOST=43.167.238.150:8082                    # 替换为你的域名或 公网IP:PORT
      # - DRONE_TLS_CERT=/data/certs/cert.pem               # 生产环境启用 HTTPS 时添加
      # - DRONE_TLS_KEY=/data/certs/key.pem                 # 生产环境启用 HTTPS 时添加
      - DRONE_SERVER_PROTO=http                             # 协议（http/https）
      - DRONE_USER_CREATE=username:wangxuancheng,admin:true  # 初始管理员用户（可选）git用户名
      - DRONE_GITEE_SCOPE=user_info projects pull_requests hook  # gitee 必须空格分隔，Drone 会自动拼接
    restart: always
```
```bash
# 启动容器（首次运行会自动拉取镜像）
docker compose -f drone-server.yml up -d

# 授权登录后 添加仓库，然后设置添加密文 ALIYUN_AK 和 ALIYUN_SK 用于 /.drone.yml 配置镜像仓库访问
```
```bash
docker run --detach \
  --volume=/var/run/docker.sock:/var/run/docker.sock \
  --volume=/artifacts:/artifacts \
  --env=DRONE_RPC_PROTO=http \
  --env=DRONE_RPC_HOST=43.167.238.150:8082 \
  --env=DRONE_RPC_SECRET=5d01c09f2ba9ad28a15148d4ce1de86c \
  --env=DRONE_RUNNER_CAPACITY=2 \
  --env=DRONE_RUNNER_NAME=my-first-runner \
  --publish=3000:3000 \
  --restart=always \
  --name=runner \
  drone/drone-runner-docker:latest

# 使用 drone validate .drone.yml 验证配置
drone validate .drone.yml

# 模拟运行
drone exec --dry-run

# 查看日志
docker logs -f drone-server

docker logs runner | grep -E "connected|error"
```

#### 安装 ArgoCD ，如pod间信问题配置亲合度同一节点
```bash
kubectl create namespace argocd
# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl create secret generic argocd-redis --from-literal=auth=<设置redis密码> -n argocd
kubectl apply -n argocd -f manifests/argo.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
kubectl get svc -n argocd -l app.kubernetes.io/name=argocd-server |grep argocd-server

# 查看密码，账号admin  IP:NodePort端口访问
kubectl -n argocd get secret \
argocd-initial-admin-secret \
-o jsonpath="{.data.password}" | base64 -d; echo
```

```bash
# 查看默认连接（如 mysql）的配置
php artisan config:show database.connections.mysql

# 或查看所有连接配置
php artisan config:show database.connections

```

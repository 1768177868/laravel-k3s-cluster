# Laravel 项目 K3s 部署操作文档

## 一、环境准备
### 1. 安装 K3s 集群# 服务器节点安装 K3s（以 Ubuntu 为例）
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
### 2. 安装 Docker 及配置 ACR 凭证# 安装 Docker
sudo apt-get update && sudo apt-get install -y docker.io
sudo systemctl enable --now docker

# 配置阿里云 ACR 凭证（替换为你的 ACR 信息）
docker login --username=your-acr-username --password=your-acr-password your-acr-domain.com
## 二、Docker 镜像构建与推送
### 1. 构建并推送镜像# 构建镜像（替换为你的 ACR 仓库地址）
docker build -t your-acr-domain.com/laravel-app:1.0.0 .

# 推送镜像
docker push your-acr-domain.com/laravel-app:1.0.0
## 三、K3s 资源文件部署
### 1. 目录结构说明项目根目录/
├─ Dockerfile
├─ k8s/
│  ├─ namespace.yaml
│  ├─ deployment.yaml
│  ├─ service.yaml
│  ├─ ingress.yaml
│  ├─ middleware.yaml
│  ├─ configmap.yaml
│  ├─ cron-job.yaml
│  ├─ nginx.conf
│  ├─ supervisord.conf
│  ├─ acr-secret.yaml
│  └─ migration-job.yaml
### 2. 创建 ACR 认证 Secretkubectl apply -f k8s/acr-secret.yaml
### 3. 应用所有资源kubectl apply -f k8s/
## 四、关键文件功能说明
### 1. 基础配置
- **namespace.yaml**：创建 `laravel` 命名空间，隔离资源  
- **acr-secret.yaml**：存储私有 ACR 仓库认证信息，支持镜像拉取  

### 2. 应用部署
- **deployment.yaml**：定义应用副本、初始化容器（数据迁移）、存储卷、镜像拉取 Secret  
- **service.yaml**：通过 ClusterIP 暴露应用 9000 端口，供 Ingress 路由转发  

### 3. 网络与代理
- **ingress.yaml**：Traefik 入口路由配置，包含域名匹配、SSL 证书解析、中间件引用  
- **middleware.yaml**：实现 URL 重写（解决 Laravel 伪静态）和认证转发  

### 4. 环境与服务
- **configmap.yaml**：注入 `.env` 环境变量，包含数据库、队列、广播等配置  
- **supervisord.conf**：管理队列工作进程，确保队列任务持续运行  

### 5. 定时与迁移
- **cron-job.yaml**：定时执行 `schedule:run`，处理 Laravel 计划任务  
- **migration-job.yaml**：手动触发数据迁移和填充的 Job 配置  

### 6. 容器配置
- **Dockerfile**：构建镜像的基础配置，包含 PHP 环境、Nginx、Supervisor 安装  
- **nginx.conf**：Nginx 伪静态规则，确保 Laravel 路由正确解析  

## 五、数据迁移与填充
### 1. 初始化容器自动执行（推荐）
在 Pod 启动前执行数据库迁移和填充，确保应用服务启动时数据库结构就绪。  
**配置位置**：`k8s/deployment.yaml` 的 `initContainers` 部分  initContainers:
- name: migrate-db
  image: your-acr-domain.com/laravel-app:1.0.0
  command: ["php", "artisan", "migrate", "--force"]
  envFrom:
  - configMapRef:
      name: laravel-env
  volumeMounts:
  - name: storage
    mountPath: /var/www/html/storage

- name: seed-db
  image: your-acr-domain.com/laravel-app:1.0.0
  command: ["php", "artisan", "db:seed", "--force"]
  envFrom:
  - configMapRef:
      name: laravel-env
  volumeMounts:
  - name: storage
    mountPath: /var/www/html/storage
### 2. 手动触发方式
#### 方式 1：通过 Job 执行# 应用迁移 Job
kubectl apply -f k8s/migration-job.yaml
# 查看 Job 状态
kubectl get job -n laravel
# 查看日志
kubectl logs <JOB_POD_NAME> -n laravel
#### 方式 2：直接进入容器# 进入应用容器
kubectl exec -it <APP_POD_NAME> -n laravel -- /bin/sh
# 执行迁移命令
php artisan migrate --force
php artisan db:seed --force
## 六、验证与维护
### 1. 状态检查# 查看 Pod 状态
kubectl get pods -n laravel

# 查看服务列表
kubectl get services -n laravel

# 查看入口路由
kubectl get ingressroute -n laravel
### 2. 日志查看
- **应用日志**：`kubectl logs <APP_POD_NAME> -n laravel`  
- **队列日志**：`kubectl exec -it <APP_POD_NAME> -n laravel -- cat /var/log/supervisor/queue.log`  
- **定时任务日志**：`kubectl logs <JOB_POD_NAME> -n laravel`  

### 3. 证书更新
Traefik 会通过 Let's Encrypt 自动续签 SSL 证书，无需手动操作。

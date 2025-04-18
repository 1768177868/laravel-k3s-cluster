# 🚀 Laravel 云原生部署方案 - K3s 实践

## 🌟 项目概述
基于轻量级 Kubernetes 发行版 K3s 的 Laravel 生产级部署方案，包含以下核心能力：

✨ **主要特性**  
- 全自动 CI/CD 流水线（镜像构建 → 安全扫描 → 集群部署）  
- 多环境配置管理（开发/测试/预发/生产）  
- 零宕机滚动更新策略  
- 弹性伸缩配置（HPA 支持）  
- 分布式追踪（Jaeger 集成）  
- 生产级监控告警（Prometheus + Grafana）  
  
## 📂 项目克隆
```bash
git clone https://gitee.com/wangxuancheng/laravel-k3s-cluster.git
```

## 🛠️ 环境准备
### 1. K3s 集群安装 Master 节点配置
```bash
sudo ufw disable
sudo swapoff -a
sudo apt update
sudo apt upgrade -y

# 设置主机名
hostnamectl set-hostname k8s-master
echo "k8s-master" | sudo tee /etc/hostname

# 使用国内镜像源安装
curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - \
  --write-kubeconfig-mode 644 \
  --tls-san <你的服务器IP> \
  --advertise-address <你的服务器IP>

# 配置环境变量
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 查看 NODE_TOKEN
cat /var/lib/rancher/k3s/server/node-token
# 查看节点
sudo k3s kubectl get nodes
# 重启服务
systemctl daemon-reload
systemctl restart k3s
# 卸载
/usr/local/bin/k3s-uninstall.sh
```

### 2. Worker 节点配置
```bash
sudo ufw disable
sudo swapoff -a
sudo apt update
sudo apt upgrade -y

# 设置主机名
hostnamectl set-hostname k8s-node1
echo "k8s-node1" | sudo tee /etc/hostname
# 使用国内镜像源安装
curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn K3S_URL=https://<MASTER_IP>:6443 K3S_TOKEN=<NODE_TOKEN> sh -
# 查看k3s服务状态
systemctl status k3s-agent
# 重启k3s服务
systemctl restart k3s-agent
# 卸载
/usr/local/bin/k3s-agent-uninstall.sh
```


### Docker 环境配置
```bash
# 安装 Docker
sudo apt-get update && sudo apt-get install -y docker.io
sudo systemctl enable --now docker

# 配置阿里云镜像加速（登录后访问 https://cr.console.aliyun.com 获取专属加速器地址）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://<your-mirror>.mirror.aliyuncs.com"]
}
EOF

sudo systemctl restart docker

# 登录阿里云镜像仓库（密码建议使用访问凭证中的临时密码）
docker login --username=<你的ACR用户名> registry.cn-hangzhou.aliyuncs.com
```
## 🐳 镜像管理
### 1. 构建与推送镜像
```bash
# 构建镜像（版本号示例：1.0.25、1.1.0-rc1）
docker build -t registry.cn-hangzhou.aliyuncs.com/xuancheng/laravel-app:<版本号> .

# 推送镜像
docker push registry.cn-hangzhou.aliyuncs.com/xuancheng/laravel-app:<版本号>
```
## ☸️ K3s 部署
### 项目结构
```
├─ Dockerfile
├─ k8s/
│  ├─ namespace.yaml       # 命名空间配置
│  ├─ deployment.yaml      # 应用部署配置
│  ├─ service.yaml         # 服务暴露配置
│  ├─ ingress.yaml         # 流量入口配置
│  ├─ middleware.yaml      # 中间件配置
│  ├─ configmap.yaml       # 环境变量配置
│  ├─ cron-job.yaml        # 定时任务
│  ├─ job.yaml             # 单次任务
│  ├─ nginx.conf           # Nginx 配置
│  ├─ supervisord.conf     # 进程管理
│  ├─ acr-secret.yaml      # 镜像仓库认证
│  ├─ app-key-secret.yaml  # laravel .env APP_KEY
│  ├─ argo.yaml            # ArgoCD 配置
│  └─ migration-job.yaml   # 数据迁移任务
```
### 部署流程
```bash
# 初始化命名空间
kubectl apply -f k8s/namespace.yaml

# 按顺序部署资源（依赖顺序：密钥 -> 配置 -> 应用）
# 1. 必须先部署密钥（Secret）
# 2. 部署配置映射（ConfigMap）
# 3. 最后部署应用（Deployment）
kubectl apply -f k8s/acr-secret.yaml -n laravel
kubectl apply -f k8s/app-key-secret.yaml -n laravel
kubectl apply -f k8s/configmap.yaml -n laravel
kubectl apply -f k8s/deployment.yaml -n laravel

# 验证部署
kubectl get all -n laravel
kubectl get ingress -n laravel
```
## 🔄 数据迁移
### 自动迁移（初始化容器）
```bash
# k8s/deployment.yaml 参考
initContainers:
  - name: migrate-db
    image: registry.cn-hangzhou.aliyuncs.com/xuancheng/laravel-app:1.0.25
    command: ["php", "artisan", "migrate", "--force"]
    envFrom:
    - configMapRef:
        name: laravel-env
```
### 手动迁移
```bash
# 通过 Job 执行
kubectl apply -f k8s/migration-job.yaml

# 查看迁移日志
kubectl logs <迁移任务Pod名称> -n laravel
```
## 🔍 运维监控
### 状态检查
```bash
# 检查 Pod 状态
kubectl get pods -n laravel
# 查看日志
kubectl logs <应用Pod名称> -n laravel
# 查看服务状态
kubectl get svc -n laravel
# 查看 ConfigMap
kubectl get configmap -n laravel 
# 查看 Secret
kubectl get secret -n laravel
```
### 资源监控
```bash
# 查看资源使用情况
kubectl top pod -n laravel
kubectl top node
```

## ⚙️ 附加配置
### 1. 镜像加速
```bash
cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  docker.io:
    endpoint:
      - "https://docker.m.daocloud.io"
      - "https://hub-mirror.c.163.com"
      - "https://registry.docker-cn.com"
  quay.io:
    endpoint:
      - "https://quay.mirrors.ustc.edu.cn"    # 中科大镜像替代:cite[1]
  registry.k8s.io:                            # 替换弃用的 k8s.gcr.io
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com/google_containers"  # 阿里云镜像路径
    rewrite:
      "^/(.*)": "/google_containers/$1"       # 路径重写规则，确保镜像层级正确
  gcr.io:
    endpoint:
      - "https://gcr.m.daocloud.io"           # DaoCloud 镜像代理
  k8s.gcr.io:                                 # 已弃用，仅保留兼容性配置
    endpoint:
      - "https://registry.cn-hangzhou.aliyuncs.com/google_containers"
  ghcr.io:
    endpoint:
      - "https://ghcr.nju.edu.cn"             # 南京大学镜像站:cite[1]
EOF

systemctl daemon-reload
systemctl restart k3s

# 配置后会在/var/lib/rancher/k3s/agent/etc/containerd下创建目录 certs.d 存放containerd mirror配置文件
```
### 2. 网络端口说明
```plaintext
TCP    2379-2380  服务器    服务器     仅对具有嵌入式 etcd 的 HA 才需要
TCP    6443       代理商    服务器     K3s 主管和 Kubernetes API 服务器
UDP    8472       所有节点  所有节点   仅 Flannel VXLAN 需要
TCP    10250      所有节点  所有节点   Kubelet 指标
UDP    51820      所有节点  所有节点   仅适用于带有 IPv4 的 Flannel Wireguard
UDP    51821      所有节点  所有节点   仅嵌入式分布式注册表（Spegel）需要
TCP    6443       所有节点  所有节点   仅嵌入式分布式注册表（Spegel）需要
```
### 3. 可视化工具
#### 安装Kuboard（访问地址 http://<服务器IP>:30080，初始账号 admin/密码 Kuboard123）
```bash
# 安装后可在仪表盘查看资源使用情况、日志流和YAML编辑
docker run -d \
  --restart=unless-stopped \
  --name=kuboard \
  -p 30080:80/tcp \
  -p 10081:10081/tcp \
  -e KUBOARD_ENDPOINT="http://<IP>:30080" \
  -v /root/kuboard-data:/data \
  eipwork/kuboard:v3
```
#### 安装 ArgoCD 
```
kubectl create namespace argocd
kubectl create secret generic argocd-redis --from-literal=auth=<设置redis密码> -n argocd
kubectl apply -n argocd -f argo.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
kubectl get svc -n argocd -l app.kubernetes.io/name=argocd-server |grep argocd-server

# 查看密码，账号admin  IP:NodePort端口访问
kubectl -n argocd get secret \
argocd-initial-admin-secret \
-o jsonpath="{.data.password}" | base64 -d
```

## 🗄️ 数据库配置
### MySQL 容器部署
```bash
# 拉取MySQL5.7镜像
docker pull mysql:5.7

docker volume rm mysql_data

# 创建并运行容器（映射3306端口，设置root密码，启用配置目录）
docker run -d \
    --name mysql5.7 \
    -p 3306:3306 \
    -v mysql_data:/var/lib/mysql \
    -e MYSQL_ROOT_PASSWORD=laravel123 \
    mysql:5.7

# 进入MySQL容器
docker exec -it mysql5.7 mysql -uroot -plaravel123

# 创建 laravel 数据库
CREATE DATABASE IF NOT EXISTS laravel;

# 创建Laravel用户（替换your_laravel_user和your_secure_password） 
CREATE USER 'laravel'@'%' IDENTIFIED BY 'laravel123';

# 授予所有数据库权限（根据需求调整权限范围）
GRANT ALL PRIVILEGES ON *.* TO 'laravel'@'%' WITH GRANT OPTION;

# 刷新权限
FLUSH PRIVILEGES;

# 退出MySQL
EXIT;
```
### Redis 容器部署
```bash
# 创建配置目录（若不存在）
mkdir -p /myredis/conf
mkdir -p /myredis/data
chmod -R 644 /myredis/conf/redis.conf

# 生成标准 Redis 配置
cat > /myredis/conf/redis.conf <<EOF
bind 0.0.0.0
protected-mode no
requirepass laravel
port 6379
EOF

docker run -d -p 0.0.0.0:6379:6379 --name myredis -v /myredis/conf/redis.conf:/etc/redis/redis.conf -v /myredis/data:/data redis redis-server /etc/redis/redis.conf --appendonly yes
```
### 🚨 故障排查
```bash
# 查看 Pod 事件
kubectl describe pod <Pod名称> -n laravel

# 查看容器日志
kubectl logs <Pod名称> -n laravel --previous

# 强制删除 Pod
kubectl delete pod <Pod名称> -n laravel --force --grace-period=0
```

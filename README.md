# 🚀 Laravel 云原生部署方案 - K3s 实践

## 🌟 项目概述
基于轻量级 Kubernetes 发行版 K3s 的 Laravel 生产级部署方案，包含以下核心能力：
  
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

# helm 安装
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# 设置主机名
hostnamectl set-hostname k8s-master
echo "k8s-master" | sudo tee /etc/hostname
# 配置hosts 增加 k8s-master
vim /etc/hosts
127.0.0.1       localhos k8s-master


# 安装
# curl -sfL https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn sh -s - \
curl -sfL https://get.k3s.io | sh -s - \
    --node-external-ip="43.167.238.150" \
    --flannel-backend=wireguard-native \
    --flannel-external-ip

# 配置config
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 查看 NODE_TOKEN
cat /var/lib/rancher/k3s/server/node-token

# 重启服务
systemctl daemon-reload
systemctl restart k3s

# 卸载
/usr/local/bin/k3s-uninstall.sh

# /etc/systemd/system/k3s.service
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
# 配置hosts 增加 k8s-node1
vim /etc/hosts
127.0.0.1       localhos k8s-node1


# 安装
# curl -Ls https://rancher-mirror.rancher.cn/k3s/k3s-install.sh | INSTALL_K3S_MIRROR=cn \
curl -sfL https://get.k3s.io | \
    K3S_URL=https://43.167.238.150:6443 \
    K3S_TOKEN=<token> sh -s - \
    --node-external-ip=43.134.106.179

# 查看k3s服务状态  
systemctl status k3s-agent

# 重启k3s服务
systemctl daemon-reload
systemctl restart k3s-agent

# 卸载
/usr/local/bin/k3s-agent-uninstall.sh

# /etc/systemd/system/k3s-agent.service
```

```bash
# K3s 客户端和服务器证书自颁发日起 365 天内有效。每次启动 K3s 时，已过期或 90 天内过期的证书都会自动更新。
# 停止 K3s
systemctl stop k3s

# 轮换证书
k3s certificate rotate

# 启动 K3s
systemctl start k3s
```

### Docker 环境配置
```bash
# 安装 Docker
sudo apt-get update && sudo apt-get install -y docker.io
sudo systemctl enable --now docker

# docker-compose up -d
apt install docker-compose

# 配置阿里云镜像加速（登录后访问 https://cr.console.aliyun.com 获取专属加速器地址）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://mirror.ccs.tencentyun.com"]
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
manifests/
├── base/                          # 基础层（必含文件）
│   ├── kustomization.yaml          # Kustomize 基础配置（核心，必须存在）
│   ├── namespace.yaml              # 命名空间定义（环境无关，如 `laravel`）
│   ├── deployment-template.yaml    # Deployment 基础模板（无环境参数）
│   ├── service.yaml                # 服务定义（ClusterIP）
│   ├── configmap-template.yaml     # ConfigMap 基础模板（公共环境变量）
│   ├── migration-job-template.yaml # 迁移 Job 基础模板（通用命令）
│   ├── secret-acr.yaml             # 镜像仓库 Secret
├── overlays/                            # 环境层（按环境拆分）
│   ├── dev/                        # 开发环境
│   │   ├── kustomization.yaml      # 开发环境 Kustomize 配置（必须）
│   │   ├── deployment.yaml         # Deployment 覆盖（副本数、资源）
│   │   ├── configmap.yaml          # ConfigMap 覆盖（开发环境变量）
│   │   ├── ingress.yaml            # 开发环境入口规则（如 dev.laravel.com）
│   │   └── secret-env.yaml         # Larvel 环境变量（dev）
│   └── prod/                       # 生产环境
│       ├── kustomization.yaml      # 生产环境 Kustomize 配置（必须）
│       ├── deployment.yaml         # Deployment 覆盖（生产参数）
│       ├── configmap.yaml          # ConfigMap 覆盖（生产环境变量）
│   │   └── secret-env.yaml         # Larvel 环境变量（prod）
│       ├── hpa.yaml                # 自动扩缩容配置
│       └── ingress.yaml            # 生产环境入口规则（如 laravel.com）
├── argo.yaml                       # ArgoCD 自身部署配置
├── argocd-application.yaml         # ArgoCD Application 配置（指向 overlays 目录）
└── README.md                       # 使用说明文档
```
### 部署流程
```bash

# 安装kustomize 部署项目
wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.6.0/kustomize_v5.6.0_linux_amd64.tar.gz
tar -xvf kustomize_v5.6.0_linux_amd64.tar.gz && mv kustomize /usr/local/bin/
```
### 查看部署文档
[manifests/README.md](./manifests/README.md)


## 🔄 数据迁移
### 自动迁移（初始化容器）
```bash
# deployment.yaml 参考
initContainers:
  - name: migrate-db
    image: registry.cn-hangzhou.aliyuncs.com/xuancheng/laravel-app
    command: ["php", "artisan", "migrate", "--force"]
    envFrom:
    - configMapRef:
        name: laravel-env
```
### 手动迁移
```bash
# 通过 Job 执行
kubectl apply -f manifests/base/migrate-job.yaml

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
kubectl top pod --all-namespaces | sort -k4 -nr
kubectl get node -owide
kubectl get pods -A
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


# 方法2
# node节点创建目录
sudo mkdir -p /etc/rancher/k3s
# 创建 containerd 配置文件
sudo tee /etc/rancher/k3s/containerd-config.yaml <<EOF
[plugins."io.containerd.grpc.v1.cri".registry.mirrors]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
    endpoint = ["https://<你的阿里云加速器地址>.mirror.aliyuncs.com"]
EOF

#ctr -n k8s.io image pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6
#ctr -n k8s.io image tag registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6 k8s.gcr.io/pause:3.6
# cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml

# 查看 K3s 服务日志
journalctl -u k3s -f  # Master 节点
journalctl -u k3s-agent -f  # Node 节点

# kubectl run test-pod --image=nginx:latest

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
# 安装后可在仪表盘查看资源使用情况、日志流和YAML编辑, nfs-client-provisioner 
# kube-system/workload/view/Deployment/eip-nfs-nfs原镜像替换 registry.cn-hangzhou.aliyuncs.com/xuancheng/nfs-subdir-external-provisioner:v4.0.2
docker run -d \
  --restart=unless-stopped \
  --name=kuboard \
  -p 30080:80/tcp \
  -p 30081:10081/udp \
  -p 30081:10081/tcp \
  -e KUBOARD_ENDPOINT="http://43.167.238.150:30080" \
  -e KUBOARD_AGENT_SERVER_UDP_PORT="30081" \
  -e KUBOARD_AGENT_SERVER_TCP_PORT="30081" \
  -v /root/kuboard-data:/data \
  registry.cn-hangzhou.aliyuncs.com/xuancheng/kuboard:v3
```


#### 安装 kubesphere （访问地址 http://<服务器IP>:30880，初始账号 admin/密码 P@88w0rd）
```bash
# wget https://github.com/kubesphere/ks-installer/releases/download/v3.4.1/kubesphere-installer.yaml
# kubectl apply -f kubesphere-installer.yaml
# kubectl get pods -n kubesphere-system

helm upgrade --install -n kubesphere-system --create-namespace ks-core https://charts.kubesphere.io/main/ks-core-1.1.4.tgz --set global.imageRegistry=swr.cn-southwest-2.myhuaweicloud.com/ks  --set extension.imageRegistry=swr.cn-southwest-2.myhuaweicloud.com/ks --debug --wait

# 卸载
helm -n kubesphere-system uninstall ks-core
# 卸载组件
helm -n kubesphere-monitoring-system uninstall whizard-monitoring whizard-monitoring-agent

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

# 仅授予 laravel 用户对 laravel 数据库的所有权限（所有表）
# GRANT ALL PRIVILEGES ON laravel.* TO 'laravel'@'%';

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
touch /myredis/conf/redis.conf
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

### 修改 k3s.service 通过调整 k3s 的配置，允许 NodePort 使用低端口（如 80/443）
```bash
sudo vim /etc/systemd/system/k3s.service
#找到 ExecStart 行，添加 --service-node-port-range=1-32767 参数：
ExecStart=/usr/local/bin/k3s \
    server \
        '--write-kubeconfig-mode' \
        '644' \
        '--tls-san' \
        '43.167.238.150' \
        '--advertise-address' \
        '43.167.238.150' \
        '--service-node-port-range' \
        '1-32767'

# 重启k3s
sudo systemctl daemon-reload
sudo systemctl restart k3s

kubectl get svc traefik -n kube-system
```

### 查看修改 traefik
```
kubectl get pods,svc -n kube-system | grep traefik
kubectl edit svc traefik -n kube-system
```


### crictl 常用命令
```bash
crictl pull <镜像名称>
crictl images
crictl pods
crictl ps -a
crictl inspect <容器 ID>
crictl start <容器 ID>
crictl stop <容器 ID>
crictl rm <容器 ID>
crictl logs <容器 ID>
crictl inspectp <Pod ID>
crictl inspecti <镜像 ID 或镜像名称>
crictl netns
crictl --help
```

### NFS
```bash
> NFS 服务器端配置（IP: 43.167.238.150）
```bash
# 更新系统并安装 NFS 服务器
sudo apt update && sudo apt install nfs-kernel-server -y

# 创建共享目录
sudo mkdir -p /data/nfs_public

# 设置目录权限（建议普通权限，避免不安全的 777）
sudo chown nobody:nogroup /data/nfs_public
sudo chmod 755 /data/nfs_public

# 编辑 NFS 共享配置（允许指定客户端 IP 访问）
sudo vim /etc/exports
# 添加以下内容（删除冗余的 fsid=0，确保 IP 与客户端一致）
/data/nfs_public 43.134.106.179(rw,sync,no_subtree_check)
/data/nfs_public 47.115.140.28(rw,sync,no_subtree_check)

# 重启 NFS 服务并重新导出共享
sudo systemctl restart nfs-kernel-server
sudo exportfs -arv

# 验证配置（确保输出包含允许的客户端 IP）
showmount -e
```

> NFS 客户端配置（IP: 43.134.106.179 和 47.115.140.28）
```bash
# 安装 NFS 客户端工具
sudo apt install nfs-common -y

# 创建挂载点
sudo mkdir -p /mnt/nfs_public

# 临时挂载（使用默认 NFS 协议，兼容 v3/v4）
sudo mount 43.167.238.150:/data/nfs_public /mnt/nfs_public

# 验证临时挂载（查看是否有共享目录内容）
ls /mnt/nfs_public

# 配置永久挂载（编辑 fstab，删除冗余的 nfs4 类型，使用默认协议）
sudo vim /etc/fstab
# 添加以下内容
43.167.238.150:/data/nfs_public /mnt/nfs_public  nfs  defaults,timeo=15,retrans=3 0 0

# 应用永久挂载配置
sudo mount -a

# 验证永久挂载（重启后生效，可用 df -h 检查）
df -h | grep nfs


# 卸载临时挂载
sudo umount /mnt/nfs_public

# 卸载永久挂载（先注释 /etc/fstab 中相关配置，再执行卸载）
sudo vim /etc/fstab  # 注释掉 43.167.238.150:/data/nfs_public /mnt/nfs_public  nfs  defaults,timeo=15,retrans=3 0 0 这一行
sudo umount /mnt/nfs_public

```

### 错误处理

```bash
# kuboard日志套件 StatefulSet/alertmanager-main
create Pod alertmanager-main-0 in StatefulSet alertmanager-main failed error: pods "alertmanager-main-0" is forbidden: error looking up service account kuboard/alertmanager-main: serviceaccount "alertmanager-main" not found


# 解决方法：
kubectl create serviceaccount alertmanager-main -n kuboard

# alertmanager-rbac.yaml 可选
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: alertmanager-main
  namespace: kuboard
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alertmanager-main
  namespace: kuboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: alertmanager-main
subjects:
- kind: ServiceAccount
  name: alertmanager-main
  namespace: kuboard


# kubectl apply -f alertmanager-rbac.yaml
```


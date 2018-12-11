#!/bin/bash

#It is a simple way to install kubernetesi'node for you!
#Author: ZhangWeiLai

cd `dirname $0`
BIN_DIR=`pwd`
cd ..
CONF_DIR=`pwd`/conf
PACKAGE_DIR=`pwd`/package
TEMP_DIR=`pwd`/temp

function error_log()
{
  datetime=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "\e[1;31m$datetime [ERROR] $1"
  echo -e "\e[0m"
}

function info_log()
{
  datetime=$(date +"%Y-%m-%d %H:%M:%S")
  echo "$datetime [INFO] $1"
}

function warning_log()
{
  datetime=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "\e[1;33m $datetime [WARN] $1"
  echo -e "\e[0m"
}

function tip_log()
{
  #datetime=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "\e[1;32m $1"
  echo -e "*******************************************************************************"
  echo -e "\e[0m"
}

#check systemc version
function checkSystemVersion(){
  centosv=`cat /etc/redhat-release`
  iscentos=`cat /etc/redhat-release | egrep 'CentOS Linux release 7\.[4-9]' | wc -l`
  if [ $iscentos -eq 0 ]
  then
    error_log "[Error] Please use CentOS 7.4 or higher version"
    exit 1
  else
    info_log "Check system version is OK!"
  fi
}

#check IP address
function checkIPAddress(){
  local IP=$1
  VALID_CHECK=$(echo $IP|awk -F. '$1<=255&&$2<=255&&$3<=255&&$4<=255{print "yes"}')

  if echo $IP|grep -E "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$" >/dev/null; then
    if [ $VALID_CHECK == "yes" ]; then
        info_log "Checking ip is OK!"
    else
        error_log "IP is not available!"
        exit 1
    fi
  else
      error_log "IP format is error!"
      exit 1
  fi

}


function stdoutLogo()
{
  echo "************************************************************"
  echo "*                                                          *"
  echo "*             LongCloud kubernetes Installer               *"
  echo "*                                                          *"
  echo "*             (kubernetes v1.11.4 for node)                *"
  echo "*                                                          *"
  echo "************************************************************"

}

function install_docker()
{
  which docker > /dev/null

  if [ $? -eq 0 ]
  then
    warning_log "Docker is installed, skip!"
  else

    tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

   yum -y install docker-engine-1.13.0-1.el7.centos

fi

  info_log "Configure docker as systemd service"
  mkdir -p /etc/systemd/system/docker.service.d

  sudo tee /etc/systemd/system/docker.service.d/env.conf <<-'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target
#Wants=docker-storage-setup.service
[Service]
EnvironmentFile=-/etc/sysconfig/docker
EnvironmentFile=-/etc/sysconfig/docker-storage
EnvironmentFile=-/etc/sysconfig/docker-network
EnvironmentFile=-/run/docker_opts.env
ExecStartPost=/sbin/iptables -P FORWARD ACCEPT
ExecStart=
ExecStart=/usr/bin/dockerd $OPTIONS \
          $DOCKER_STORAGE_OPTIONS \
          $DOCKER_NETWORK_OPTIONS \
          $BLOCK_REGISTRY \
          $INSECURE_REGISTRY \
          $DOCKER_OPTS
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
MountFlags=slave
TimeoutStartSec=120min

[Install]
WantedBy=multi-user.target
EOF

#sudo tee /etc/sysconfig/docker <<-'EOF'
#OPTIONS='-g /data/paas/docker/data -H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock --storage-driver=overlay2 --storage-opt overlay2.override_kernel_check=1 --insecure-registry $1:5000 '
#EOF

info_log "Configure docker in /etc/sysconfig/docker"
sed -e "s/\$REGISTRY_IP/$1/g" $CONF_DIR/docker.conf > /etc/sysconfig/docker

info_log "Restart docker"

systemctl daemon-reload
systemctl restart docker
systemctl enable docker.service
}

function prepare_kube_install_environment()
{
  info_log "Close system's swap"
  swapoff -a
  sed -i "s/\/dev\/mapper\/centos-swap/\#\/dev\/mapper\/centos-swap/g" /etc/fstab
  mount -a

  mkdir -p /etc/kubernetes/

  info_log "Unzip kubernetes-server-linux-amd64.tar.gz"
  tar -zxvf $PACKAGE_DIR/kubernetes-server-linux-amd64.tar.gz -C $TEMP_DIR

  info_log "Configure the public configuration file."
  sed -e "s/\$KUBE_MASTER_IP/$1/g" $CONF_DIR/kube_public_configuration.conf > /etc/kubernetes/config
}

function install_kube_proxy()
{

  systemctl stop kube-proxy > /dev/null

  cp $TEMP_DIR/kubernetes/server/bin/kube-proxy /usr/bin/

  info_log "Configure kube-proxy as systemd service"
  sudo tee /etc/systemd/system/kube-proxy.service <<-'EOF'
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
Requires=network.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/proxy
ExecStart=/usr/bin/kube-proxy \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_MASTER \
	    $KUBE_PROXY_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  info_log "Configure kube-proxy in /etc/kubernetes/proxy"
  sed -e "s/\$KUBE_MASTER_IP/$1/g" $CONF_DIR/kube_proxy.conf > /etc/kubernetes/proxy

  info_log "Restart kube-proxy"
  systemctl daemon-reload
  systemctl restart kube-proxy
  systemctl enable kube-proxy.service

}

function install_kube_kubelet()
{

  systemctl stop kubelet > /dev/null

  cp $TEMP_DIR/kubernetes/server/bin/kubelet /usr/bin/

  info_log "Configure kubelet as systemd service"
sudo tee /etc/systemd/system/kubelet.service <<-'EOF'
[Unit]
Description=Kubernetes Kubelet Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/kubelet
ExecStart=/usr/bin/kubelet \
    $KUBE_LOGTOSTDERR \
    $KUBE_LOG_LEVEL \
    $KUBELET_API_SERVER \
    $KUBELET_ADDRESS \
    $KUBELET_PORT \
    $KUBELET_HOSTNAME \
    $KUBE_ALLOW_PRIV \
    $KUBELET_POD_INFRA_CONTAINER \
    $KUBELET_KUBECONFIG \
    $KUBELET_ARGS
#Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  info_log "Configure kubelet in /etc/kubernetes/kubelet"
  sed -e "s/\$REGISTRY_IP/$1/g" $CONF_DIR/kube_kubelet.conf > /etc/kubernetes/kubelet

  info_log "Configure kubelet.kubeconfig in /etc/kubernetes/kubelet.kubeconfig"
  sed -e "s/\$KUBE_MASTER_IP/$1/g" $CONF_DIR/kubelet.kubeconfig > /etc/kubernetes/kubelet.kubeconfig

  info_log "Restart kubelet"
  systemctl daemon-reload
  systemctl restart kubelet
  systemctl enable kubelet.service

}

function install_flanneld()
{
   mkdir -p $TEMP_DIR/flannel/

  info_log "Unzip flannel-v0.10.0-linux-amd64.tar.gz"
  tar -zxvf $PACKAGE_DIR/flannel-v0.10.0-linux-amd64.tar.gz -C $TEMP_DIR/flannel/

  systemctl stop flanneld > /dev/null

  cp $TEMP_DIR/flannel/flanneld /usr/bin/
  cp $TEMP_DIR/flannel/mk-docker-opts.sh /usr/bin/

  info_log "Configure flanneld as systemd service"

  sudo tee /etc/systemd/system/flanneld.service <<-'EOF'
[Unit]
Description=flanneld overlay address etcd agent
After=network.target
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/flanneld
ExecStart=/usr/bin/flanneld -etcd-endpoints=${FLANNEL_ETCD} $FLANNEL_OPTIONS

[Install]
RequiredBy=docker.service
WantedBy=muti-user.target
EOF

  info_log "Configure flanneld in /etc/sysconfig/flanneld"
  sed -e "s/\$ETCD_IP/$1/g" $CONF_DIR/flanneld.conf > /etc/sysconfig/flanneld

  info_log "Restart flanneld"

  systemctl daemon-reload
  systemctl enable flanneld

  info_log "Configure docker0 bridge network same as flannl0"

  etcdctl set /coreos.com/network/config '{"Network":"10.1.0.0/16"}'
  systemctl stop docker
  systemctl restart flanneld
  mk-docker-opts.sh -c
  systemctl restart docker
  systemctl restart kubelet

}

################################################################
# The script will execute follow code  
################################################################ 

stdoutLogo

IP=$1

tip_log "First, Checking System environment......"
checkSystemVersion
checkIPAddress $IP
info_log "Everything are OK!"

echo ""

mkdir -p $TEMP_DIR

tip_log "Step 1/5 Install flanneld......"
install_flanneld $IP
info_log "Flanneld is installed successfully!"

tip_log "Step 2/5 Install docker......"
install_docker $IP
info_log "Docker is installed successfully!"

tip_log "Step 3/5 Prepare environment for kubernetes......"
prepare_kube_install_environment $IP
info_log "Environment is ready!"

tip_log "Step 4/5 Install kube-proxy......"
install_kube_proxy $IP
info_log "Kube-proxy is installed successfully!"

tip_log "Step 5/5 Install kubelet......"
install_kube_kubelet $IP
info_log "Kubelet is installed successfully!"

tip_log "Kubernetes's node is installed successfully!"


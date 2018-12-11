#!/bin/bash

#It is a simple way to install kubernetes for you!
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
  log_str="$datetime [ERROR] $1"
  echo -e "\e[1;31m $log_str"
  echo -e "\e[0m"
}

function info_log()
{
  datetime=$(date +"%Y-%m-%d %H:%M:%S")
  log_str="$datetime [INFO] $1"
  echo "$log_str"
}

function warning_log()
{
  datetime=$(date +"%Y-%m-%d %H:%M:%S")
  log_str="$datetime [WARN] $1"
  echo -e "\e[1;33m $log_str"
  echo -e "\e[0m"
}

function tip_log()
{
  echo -e "\e[1;32m$1"
  split_str="*******************************************************************************"
  echo -e "$split_str"
  echo -e "\e[0m"
}

function echo_logo()
{
  echo $1
}

#check systemc version
function checkSystemVersion(){
  centosv=`cat /etc/redhat-release`
  iscentos=`cat /etc/redhat-release | egrep 'CentOS Linux release 7\.[3-9]' | wc -l`
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

  if [ $IP =="" ]; then
    error_log "Please input the IP of Master node!"
    exit 1
  fi

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
  echo_log "************************************************************"
  echo_log "*                                                          *"
  echo_log "*             LongCloud kubernetes Installer               *"
  echo_log "*                                                          *"
  echo_log "*                 (kubernetes v1.11.4)                     *"
  echo_log "*                                                          *"
  echo_log "************************************************************"

}


function install_etcd()
{
  etcd_name=etcd-v3.1.11-linux-amd64
  mkdir -p /var/lib/etcd/
  mkdir -p /etc/etcd/
  
  systemctl stop etcd
  tar -zxvf $PACKAGE_DIR/$etcd_name.tar.gz -C $TEMP_DIR
  cp $TEMP_DIR/$etcd_name/etcd /usr/bin
  cp $TEMP_DIR/$etcd_name/etcdctl /usr/bin

  info_log "Configure etcd as systemd service"
  sudo tee /etc/systemd/system/etcd.service <<-'EOF'
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=-/etc/etcd/etcd.conf
ExecStart=/usr/bin/etcd --name=${ETCD_NAME} --data-dir=${ETCD_DATA_DIR} --listen-client-urls=${ETCD_LISTEN_CLIENT_URLS}
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  info_log "Configure etcd in /etc/etcd/etcd.conf"
  cp $CONF_DIR/etcd.conf /etc/etcd/

  info_log "Restart etcd"
  systemctl daemon-reload
  systemctl restart etcd
  systemctl enable etcd.service

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

function install_kube_apiserver()
{
  
  systemctl stop kube-apiserver > /dev/null

  cp $TEMP_DIR/kubernetes/server/bin/kube-apiserver /usr/bin/
  cp $TEMP_DIR/kubernetes/server/bin/kubectl /usr/bin/

  info_log "Configure kube-apiserver as systemd service"
  sudo tee /etc/systemd/system/kube-apiserver.service <<-'EOF'
[Unit]
Description=Kubernetes API Service
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
#Wants=docker.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/apiserver
ExecStart=/usr/bin/kube-apiserver \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_ETCD_SERVERS \
	    $KUBE_API_ADDRESS \
	    $KUBE_API_PORT \
	    $KUBELET_PORT \
	    $KUBE_ALLOW_PRIV \
	    $KUBE_SERVICE_ADDRESSES_RANGE \
            $KUBE_SERVICE_PORTS_RANGE \
	    $KUBE_ADMISSION_CONTROL \
	    $KUBE_API_ARGS
Restart=on-failure
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  info_log "Configure kube-apiserver in /etc/kubernetes/apiserver"
  sed -e "s/\$KUBE_MASTER_IP/$1/g" $CONF_DIR/kube_apiserver.conf > /etc/kubernetes/apiserver

  info_log "Restart kube-apiserver"
  systemctl daemon-reload
  systemctl restart kube-apiserver
  systemctl enable kube-apiserver.service

}


function install_kube_controller_manager()
{
  systemctl stop kube-controller-manager > /dev/null

  cp $TEMP_DIR/kubernetes/server/bin/kube-controller-manager /usr/bin/

  info_log "Configure kube-controller-manager as systemd service"
  sudo tee /etc/systemd/system/kube-controller-manager.service <<-'EOF'
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=kube-apiserver.service
Requires=kube-apiserver.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/controller-manager
ExecStart=/usr/bin/kube-controller-manager \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_MASTER \
	    $KUBE_CONTROLLER_MANAGER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  info_log "Configure kube-controller-manager in /etc/kubernetes/controller-manager"
  sed -e "s/\$KUBE_MASTER_IP/$1/g" $CONF_DIR/kube_controller_manager.conf > /etc/kubernetes/controller-manager

  info_log "Restart kube-controller-manager"
  systemctl daemon-reload
  systemctl restart kube-controller-manager
  systemctl enable kube-controller-manager.service

}

function install_kube_scheduler()
{
  systemctl stop kube-scheduler > /dev/null

  cp $TEMP_DIR/kubernetes/server/bin/kube-scheduler /usr/bin/

  info_log "Configure kube-scheduler as systemd service"
  sudo tee /etc/systemd/system/kube-scheduler.service <<-'EOF'
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=kube-apiserver.service
Requires=kube-apiserver.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/scheduler
ExecStart=/usr/bin/kube-scheduler \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_MASTER \
	    $KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  info_log "Configure kube-scheduler in /etc/kubernetes/scheduler"
  sed -e "s/\$KUBE_MASTER_IP/$1/g" $CONF_DIR/kube_scheduler.conf > /etc/kubernetes/scheduler

  info_log "Restart kube-scheduler"
  systemctl daemon-reload
  systemctl restart kube-scheduler
  systemctl enable kube-scheduler.service

}

function install_registry()
{
   
   docker load < $PACKAGE_DIR/registry-2.6.tar

   mkdir -p /data/docker/registry

   docker stop registry2
   docker rm registry2

   docker run -d \
    --name registry2 \
    --restart=always \
    -p 5000:5000 \
    -v /data/docker/registry:/var/lib/registry \
    registry:2.6
}

function install_pod_infrastructure()
{
  docker load < $PACKAGE_DIR/rhel7-pod-infrastructure-latest.tar
  docker tag registry.access.redhat.com/rhel7/pod-infrastructure:latest $1:5000/library/pod-infrastructure:latest
  docker push $1:5000/library/pod-infrastructure:latest
  docker rmi registry.access.redhat.com/rhel7/pod-infrastructure:latest
}

function install_nginx_ingress()
{
  docker load < $PACKAGE_DIR/nginx-ingress-controller-0.21.0.tar
  docker tag quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.21.0 $1:5000/library/nginx-ingress-controller:0.21.0
  docker push $1:5000/library/nginx-ingress-controller:0.21.0
  docker rmi quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.21.0
  
  host_name=`hostname`
  sed -e "s/\$MASTER_IP/$1/g" -e "s/\$NODE_NAME/$host_name/g" -e "s/\$REGISTRY_IP/$1/g" $CONF_DIR/nginx_ingress.yaml > $TEMP_DIR/nginx_ingress.yaml

  kubectl apply -f $TEMP_DIR/nginx_ingress.yaml
 
}

function install_kubernetes_dashboard()
{
   docker load < $PACKAGE_DIR/kubernetes-dashboard-1.8.3.tar
   docker tag reg.qiniu.com/k8s/kubernetes-dashboard-amd64:v1.8.3 $1:5000/library/kubernetes-dashboard-amd64:v1.8.3
   docker push $1:5000/library/kubernetes-dashboard-amd64:v1.8.3
   docker rmi reg.qiniu.com/k8s/kubernetes-dashboard-amd64:v1.8.3
   
   sed -e "s/\$REGISTRY_IP/$1/g" -e "s/\$MASTER_IP/$1/g" $CONF_DIR/kubernetes-dashboard.yaml > $TEMP_DIR/kubernetes-dashboard.yaml
   kubectl apply -f $TEMP_DIR/kubernetes-dashboard.yaml
   kubectl apply -f $CONF_DIR/kubernetes-dashboard-admin.rbac.yaml
}


function install_baseimage_centos7()
{
  docker load < $PACKAGE_DIR/centos-7.0.tar
  docker tag centos:7.0 $1:5000/library/centos:7.0
  docker push $1:5000/library/centos:7.0
  docker rmi centos:7.0
}

function install_jenkins()
{
  mkdir -p /data/jenkins_data/self_plugins
  
  docker load < $PACKAGE_DIR/jenkins-lts.tar
  docker stop jenkins
  docker rm jenkins
  docker run --name=jenkins \
           --restart=always \
           -d -u root \
           -m 1024m \
           -p 8010:8080 -p 50000:50000 \
           -v /data/jenkins_data:/var/jenkins_home \
           -v /data/jenkins_data/self_plugins:/opt \
           -v /var/run/docker.sock:/var/run/docker.sock \
           -v $(which docker):/usr/bin/docker \
           -v /usr/lib64/libltdl.so.7:/usr/lib/x86_64-linux-gnu/libltdl.so.7 \
           -e LANG=en_US.UTF-8 \
           -e LANGUAGE=en_US:en \
           -e LC_ALL=en_US.UTF-8 \
           -e TZ=Asia/Shanghai \
           jenkins/jenkins:lts

   cd /data/jenkins_data/self_plugins/
   tar -zxvf $PACKAGE_DIR/apache-maven-3.6.0-bin.tar.gz -C /data/jenkins_data/self_plugins

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

tip_log "Step 1/12 Install etcd......"
install_etcd $IP
info_log "Etcd is installed successfully!"

tip_log "Step2/12 Prepare environment for kubernetes......"
prepare_kube_install_environment $IP
info_log "Environment is ready!"

tip_log "Step 3/12 Install kube-api-server......"
install_kube_apiserver $IP
info_log "Kube-api-server is installed successfully!"

tip_log "Step 4/12 Install kube-controller-manager......"
install_kube_controller_manager $IP
info_log "Kube-controller-manager is installed successfully!"

tip_log "Step 5/12 Install kube-scheduler......"
install_kube_scheduler $IP
info_log "Kube-scheduler is installed successfully!"

tip_log "Step 6/12 Install kube-node......"
$BIN_DIR/kube-node-installer.sh $IP
info_log "kube-node is installed successfully!"

tip_log "Step 7/12 Install docker registry......"
install_registry
info_log "Docker registry is installed successfully!"

tip_log "Step 8/12 Install pod infrastructure......"
install_pod_infrastructure $IP
info_log "Pod infrastructure is installed successfully!"

tip_log "Step 9/12 Install nginx-ingress......"
install_nginx_ingress $IP
info_log "Nginx-ingress is installed successfully!"

tip_log "Step 10/12 Install kubernetes dashboard......"
install_kubernetes_dashboard $IP
info_log "Kubernetes dashboard is installed successfully!"


tip_log "Step 11/12 Install base image of centos 7.0......"
install_baseimage_centos7 $IP
info_log "Base image of centos 7.0 is installed successfully!"

tip_log "Step 12/12 Install jenkins......"
install_jenkins
info_log "Jenkins is installed successfully!"

echo -e "\e[1;32mCongratulations! Kubernetes install successfully!"
echo -e "\e[0m"

echo "Install completely. Now you can visit kubernetes's dashboard use: http://$IP:8080/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/cluster?namespace=default"
echo "Also, you can visit jenkins use: http://$IP:8010"

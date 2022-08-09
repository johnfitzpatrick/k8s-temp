#!/bin/bash

MYIP=$(curl -s http://checkip.amazonaws.com)

INTEGRATION={{integration}}/kong

function install-kong-gw {


    source $INTEGRATION/kong-setup/variables.sh

    # Make sure there are no containers running
    docker stop $(docker ps -a -q) || :
    docker rm $(docker ps -a -q) || :


  pushd $INTEGRATION/kong-setup/
    # Create the directory for storing certificates, configuration and logs

# Following for setup on AVL
# Obtain docker certificates and clone course repo
./setup-docker.sh
git clone https://github.com/Kong/kong-course-gateway-ops-for-kubernetes.git
cd kong-course-gateway-ops-for-kubernetes

# Create the Kind Cluster Config
# KIND_HOST=`getent hosts kongcluster | cut -d " " -f1`
KIND_HOST=$(curl -s http://checkip.amazonaws.com)



cat << EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: avl
networking:
  apiServerAddress: ${KIND_HOST}
  apiServerPort: 8443
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
nodes:
  - role: control-plane
    extraPortMappings:
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30000
      containerPort: 30000
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30001
      containerPort: 30001
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30002
      containerPort: 30002
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30003
      containerPort: 30003
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30004
      containerPort: 30004
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30005
      containerPort: 30005
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30006
      containerPort: 30006
    - listenAddress: "0.0.0.0"
      protocol: TCP
      hostPort: 30443
      containerPort: 30443
EOF

# Deploy the Kind Cluster
kind create cluster --config kind-config.yaml

# Deploy the Kind Cluster
mv /home/labuser/kong-course-gateway-ops-for-kubernetes/.kube /home/labuser
export KUBECONFIG=/home/labuser/.kube/config
kubectl apply -f https://projectcalico.docs.tigera.io/manifests/calico.yaml
kubectl -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true

# Create and Stage the SSL Certificates to K8s
openssl rand -writerand .rnd
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
kubectl create namespace kong
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong

# Stage Resources and Set Password
kubectl create secret generic kong-enterprise-license -n kong --from-file=license=/etc/kong/license.json
cat << EOF > admin_gui_session_conf
{
    "cookie_name":"admin_session",
    "cookie_samesite":"off",
    "secret":"kong",
    "cookie_secure":false,
    "storage":"kong"
}
EOF

# Stage Resources and Set Password
kubectl create secret generic kong-session-config -n kong --from-file=admin_gui_session_conf
kubectl create secret generic kong-enterprise-superuser-password --from-literal=password=password -n kong

cat << EOF > portal_gui_session_conf
{
    "cookie_name":"portal_session",
    "cookie_samesite":"off",
    "secret":"kong",
    "cookie_secure":true,
    "cookie_domain":".labs.konghq.com",
    "storage":"kong"
}
EOF

# Stage Portal Config and Dataplane Certs & License
kubectl create secret generic kong-portal-session-config -n kong --from-file=portal_session_conf=portal_gui_session_conf
kubectl create namespace kong-dp
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp
kubectl create secret generic kong-enterprise-license -n kong-dp --from-file=license=/etc/kong/license.json

# Add Kong Helm Repo & Update, Add Values
helm repo add kong https://charts.konghq.com
helm repo update
sed -i "s/admin_gui_url:.*/admin_gui_url: https:\/\/$KONG_MANAGER_URI/g" ./base/cp-values.yaml
sed -i "s/admin_api_url:.*/admin_api_url: https:\/\/$KONG_ADMIN_API_URI/g" ./base/cp-values.yaml
sed -i "s/admin_api_uri:.*/admin_api_uri: $KONG_ADMIN_API_URI/g" ./base/cp-values.yaml
sed -i "s/proxy_url:.*/proxy_url: https:\/\/$KONG_PROXY_URI/g" ./base/cp-values.yaml
sed -i "s/portal_api_url:.*/portal_api_url: https:\/\/$KONG_PORTAL_API_URI/g" ./base/cp-values.yaml
sed -i "s/portal_gui_host:.*/portal_gui_host: $KONG_PORTAL_GUI_HOST/g" ./base/cp-values.yaml

# Deploy Kong Control Plane with Environment Vars
helm install -f ./base/cp-values.yaml kong kong/kong -n kong \
--set manager.ingress.hostname=${KONG_MANAGER_URI} \
--set portal.ingress.hostname=${KONG_PORTAL_GUI_HOST} \
--set admin.ingress.hostname=${KONG_ADMIN_API_URI} \
--set portalapi.ingress.hostname=${KONG_PORTAL_API_URI}

# Deploy Kong Data Plane with Vars and Monitor
helm install -f ./base/dp-values.yaml kong-dp kong/kong -n kong-dp \
--set proxy.ingress.hostname=${KONG_PROXY_URI}











    rm -rf /srv/shared/kong
    mkdir -p /srv/shared/kong

    # Copy files required for Kong to startup and assign permissons
    cp -R ssl-certs /srv/shared/kong
    cp -R keycloak /srv/shared/kong

    # Create Log files
    mkdir -p /srv/shared/kong/logs
    touch $(grep '/srv/shared/kong/logs' "${INTEGRATION}/kong-setup/docker/docker-compose-variant-b.yml" | awk '{print $2}' | xargs)
    
    
    # Change permissions for Kong directory
    chmod -R a+rw /srv/shared/kong/*

    # Create a hidden directory for solution and grading
    rm -rf /tmp/.shared
    mkdir -p /tmp/.shared


    # These files are copied to test the grading and solution scripts manually within the Trueability environment

    cp -R $INTEGRATION/kong-setup/startup/deck/variant_b /tmp/.shared/deck
    cp -R $INTEGRATION/assessments/kong-gateway-associate/templates/solution /tmp/.shared/s
    cp -R $INTEGRATION/assessments/kong-gateway-associate/templates/grading /tmp/.shared/g
    
    # Scripts to Instantiate initial variables for 02-kga-pbtb
    mkdir -p /tmp/.shared/startup
    cp -R $INTEGRATION/kong-setup/startup/scripts/variant_b/02-kga-pbtb_initial_ids.sh /tmp/.shared/startup
    cp -R $INTEGRATION/kong-setup/docker/docker-compose-variant-b.yml /tmp/.shared/startup

    # If the hostname is something other than localhost, we need to add an entry into /etc/hosts
    if "{{konggwname}}" != "localhost"; then
        sed -i '/{{konggwname}}/d' /etc/hosts
        echo "{{node1.private_ipv4_address}}    {{konggwname}}" >>/etc/hosts
    fi
    
    # Keycloak host name must be resolved to localhost

    echo "127.0.0.1 keycloak" >> /etc/hosts

    # Start Docker Containers

    docker-compose -f $INTEGRATION/kong-setup/docker/docker-compose-variant-b.yml up -d db kong-cp kong-migrations kong-dp keycloak httpbin.local mockbin.local
    http POST "{{konggwname}}:8001/licenses" payload=@$INTEGRATION/kong-setup/license/license.json Kong-Admin-Token:mytoken --ignore-stdin
    docker-compose -f $INTEGRATION/kong-setup/docker/docker-compose-variant-b.yml stop kong-cp
    docker-compose -f $INTEGRATION/kong-setup/docker/docker-compose-variant-b.yml rm -f kong-cp
    docker-compose -f $INTEGRATION/kong-setup/docker/docker-compose-variant-b.yml up -d kong-cp
    docker-compose -f $INTEGRATION/kong-setup/docker/docker-compose-variant-b.yml up -d deck

    popd

    # Load up config then grab IDs for question 02-kga-pbtb

    sleep 5
    
    # Execute script required for grading for PBTB Question 2
    /tmp/.shared/startup/02-kga-pbtb_initial_ids.sh
    
}

install-kong-gw

# Install Pre-requisite applications
apt install -y npm
npm install --global -y jsonwebtokencli

# We don't want users to access the solution and grading scripts
chmod 700 /usr/local/bin/deck
chmod -R 700 /tmp/.shared/*
chmod a+rx $INTEGRATION/assessments/kong-gateway-associate/templates/solution/variant_b/04-KGA-PBTB-solution.sh
chmod a+rx /tmp/.shared/startup/ids.sh



#Terminal autostart
# ln -sf {{node.desktop.user.home_dir}}/Desktop/pantheon-terminal.desktop {{node.desktop.user.home_dir}}/.config/autostart/
sed -i 's/^Exec=.*/& http:\/\/{{konggwname}}:8002/' {{node.desktop.user.home_dir}}/.config/autostart/Instructions.desktop

#!/bin/bash

set -e

CLUSTER_NAME=$1

#API loadbalancers public hostname
API_LB_HOSTNAME=test.example.com
#Load balancers private ip address
KUBERNETES_ADDRESS=10.100.100.1
#all master/controllers nodes public hostnames
MASTER_HOSTNAMES=(master1 master2 master3)
#all workers nodes public hostnames
WORKERS_HOSTNAMES=(worker1 worker2 worker3)
#all workers nodes private ip addresses
WORKERS_PRIVATE=(10.100.100.1 10.100.100.2 10.100.100.3)
CERT_HOSTNAME=10.32.0.1,127.0.0.1,localhost,kubernetes.default
WORKER_USER="user"
CONTROLLER_USER="user"

mkdir -p output/${CLUSTER_NAME}-cluster
OUT_DIR="./output/${CLUSTER_NAME}-cluster"
CSR_DIR="./csr"

#A1 generate all the certs needed
function gen_ca()
{
  printf "\\nGenerating Certificate Authority\\n\\n"
  cfssl gencert -initca ${CSR_DIR}/ca-csr.json | cfssljson -bare ${OUT_DIR}/ca
}

#A2
function gen_admin_certs()
{
  printf "\\n\\nGenerating Admin certs\\n\\n"

  cfssl gencert \
  -ca=${OUT_DIR}/ca.pem \
  -ca-key=${OUT_DIR}/ca-key.pem \
  -config="${CSR_DIR}"/ca-config.json \
  -profile=kubernetes \
  ${CSR_DIR}/admin-csr.json | cfssljson -bare ${OUT_DIR}/admin

}

#A3
#TO-DO worker private IPS
function gen_kubelet_certs()
{

  printf "\\n\\nGenerating Kubelets certs for each worker\\n\\n"

  for w in ${WORKERS_HOSTNAMES[@]}; do

    printf "\\n\\n$w\\n\\n"

    cat > ${OUT_DIR}/"$w"-csr.json << EOF
{
  "CN": "system:node:$w",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

    cfssl gencert \
      -ca=${OUT_DIR}/ca.pem  \
      -ca-key=${OUT_DIR}/ca-key.pem  \
      -config="${CSR_DIR}"/ca-config.json \
      -hostname="${WORKERS_PRIVATE[$w]}","$w" \
      -profile=kubernetes \
      ${OUT_DIR}/"$w"-csr.json | cfssljson -bare ${OUT_DIR}/"$w"

  done

}

#A3
function gen_kube_controller_manager_certs()
{

  printf "\\n\\nGenerating Kube Controller Manager certs"
  cfssl gencert \
    -ca=${OUT_DIR}/ca.pem  \
    -ca-key=${OUT_DIR}/ca-key.pem  \
    -config="${CSR_DIR}"/ca-config.json \
    -profile=kubernetes \
    ${CSR_DIR}/kube-controller-manager-csr.json | cfssljson -bare ${OUT_DIR}/kube-controller-manager

}

#A4
function gen_kube_proxy_certs()
{

  printf "\\n\\nGenerating Kube Proxy certs\\n\\n"
  cfssl gencert \
    -ca=${OUT_DIR}/ca.pem  \
    -ca-key=${OUT_DIR}/ca-key.pem  \
    -config="${CSR_DIR}"/ca-config.json \
    -profile=kubernetes \
    ${CSR_DIR}/kube-proxy-csr.json | cfssljson -bare ${OUT_DIR}/kube-proxy

}

#A5
function gen_kube_scheduler_certs()
{

    printf "\\n\\nGenerating Kube Scheduler certs\\n\\n"
  cfssl gencert \
    -ca=${OUT_DIR}/ca.pem  \
    -ca-key=${OUT_DIR}/ca-key.pem  \
    -config="${CSR_DIR}"/ca-config.json \
    -profile=kubernetes \
    ${CSR_DIR}/kube-scheduler-csr.json | cfssljson -bare ${OUT_DIR}/kube-scheduler
}

#A6
function gen_kube_api_certs()
{
  printf "\\n\\nGenerating Kube API server certs\\n\\n"

  #Add the hostname of all the controller nodes
  for c in "${MASTER_HOSTNAMES[@]}"; do
    CERT_HOSTNAME="${CERT_HOSTNAME},${MASTER_HOSTNAMES[$c]}"
  done

  cfssl gencert \
    -ca=${OUT_DIR}/ca.pem  \
    -ca-key=${OUT_DIR}/ca-key.pem  \
    -config="${CSR_DIR}"/ca-config.json \
    -hostname="${CERT_HOSTNAME}" \
    -profile=kubernetes \
    "${CSR_DIR}"/kubernetes-api-csr.json | cfssljson -bare ${OUT_DIR}/kubernetes-api

}

#A7
function gen_kube_svc_account_certs()
{

  printf "\\n\\nGenerating Kube Service account certs\\n\\n"

  cfssl gencert \
    -ca=${OUT_DIR}/ca.pem  \
    -ca-key=${OUT_DIR}/ca-key.pem  \
    -config="${CSR_DIR}"/ca-config.json \
    -profile=kubernetes \
    ${CSR_DIR}/service-account-csr.json | cfssljson -bare ${OUT_DIR}/service-account

}

#A8 Move certificate files to the worker nodes
function copy_worker_certs()
{

  printf "\\n\\nCopying certificates to the worker nodes\\n\\n"
  for w in "${WORKERS_HOSTNAMES[@]}"; do
    scp ca.pem "$w"-key.pem "$w".pem ${WORKER_USER}@"$w":~/
  done
}

#A9
function copy_controller_certs()
{

  printf "\\n\\nCopying certificates to the controller nodes\\n\\n"
  for c in "${MASTER_HOSTNAMES[@]}"; do
    scp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
      service-account-key.pem service-account.pem ${CONTROLLER_USER}@"${MASTER_HOSTNAMES[$c]}":~/
    done
}

#B1 Generate all the kube configs for all worker kubelets
function gen_kubeconfig_worker()
{
  printf "\\n\\nGenerating Kube config for worker nodes\\n\\n"
  for w in "${WORKERS_HOSTNAMES[@]}"; do
    kubectl config set-cluster "${CLUSTER_NAME}" \
      --certificate-authority=${OUT_DIR}/ca.pem \
      --embed-certs=true \
      --server=https://"${KUBERNETES_ADDRESS}":6443 \
      --kubeconfig=${OUT_DIR}/"$w".kubeconfig

    kubectl config set-credentials system:node:"$w" \
      --client-certificate=${OUT_DIR}/"$w".pem \
      --client-key=${OUT_DIR}/"$w"-key.pem \
      --embed-certs=true \
      --kubeconfig=${OUT_DIR}/"$w".kubeconfig

    kubectl config set-context "${CLUSTER_NAME}" \
      --cluster="${CLUSTER_NAME}" \
      --user=system:node:"$w" \
      --kubeconfig=${OUT_DIR}/"$w".kubeconfig

    kubectl config use-context "${CLUSTER_NAME}" --kubeconfig=${OUT_DIR}/"$w".kubeconfig
  done
}

#B2
function gen_kubeconfig_proxy()
{
  printf "\\n\\nGenerating Kube config for kube proxy\\n\\n"

  kubectl config set-cluster "${CLUSTER_NAME}" \
  --certificate-authority=${OUT_DIR}/ca.pem \
  --embed-certs=true \
  --server=https://"${KUBERNETES_ADDRESS}":6443 \
  --kubeconfig=${OUT_DIR}/kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=${OUT_DIR}/kube-proxy.pem \
    --client-key=${OUT_DIR}/kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=${OUT_DIR}/kube-proxy.kubeconfig

  kubectl config set-context "${CLUSTER_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user=system:kube-proxy \
    --kubeconfig=${OUT_DIR}/kube-proxy.kubeconfig

  kubectl config use-context "${CLUSTER_NAME}" --kubeconfig=${OUT_DIR}/kube-proxy.kubeconfig

}

#B3
function gen_kubeconfig_controller()
{
  printf "\\n\\nGenerating Kube config for controllers\\n\\n"

  kubectl config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority=${OUT_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=${OUT_DIR}/kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=${OUT_DIR}/kube-controller-manager.pem \
    --client-key=${OUT_DIR}/kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=${OUT_DIR}/kube-controller-manager.kubeconfig

  kubectl config set-context "${CLUSTER_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user=system:kube-controller-manager \
    --kubeconfig=${OUT_DIR}/kube-controller-manager.kubeconfig

  kubectl config use-context "${CLUSTER_NAME}" --kubeconfig=${OUT_DIR}/kube-controller-manager.kubeconfig

}

#B4
function gen_kubeconfig_scheduler()
{
  printf "\\n\\nGenerating Kube config for scheduler\\n\\n"

    kubectl config set-cluster "${CLUSTER_NAME}" \
      --certificate-authority=${OUT_DIR}/ca.pem \
      --embed-certs=true \
      --server=https://127.0.0.1:6443 \
      --kubeconfig=${OUT_DIR}/kube-scheduler.kubeconfig

    kubectl config set-credentials system:kube-scheduler \
      --client-certificate=${OUT_DIR}/kube-scheduler.pem \
      --client-key=${OUT_DIR}/kube-scheduler-key.pem \
      --embed-certs=true \
      --kubeconfig=${OUT_DIR}/kube-scheduler.kubeconfig

    kubectl config set-context "${CLUSTER_NAME}" \
      --cluster="${CLUSTER_NAME}" \
      --user=system:kube-scheduler \
      --kubeconfig=${OUT_DIR}/kube-scheduler.kubeconfig

    kubectl config use-context "${CLUSTER_NAME}" --kubeconfig=${OUT_DIR}/kube-scheduler.kubeconfig
}

#B5
function gen_kubeconfig_admin()
{
  printf "\\n\\nGenerating Kube config for admin\\n\\n"
  kubectl config set-cluster "${CLUSTER_NAME}" \
     --certificate-authority=${OUT_DIR}/ca.pem \
     --embed-certs=true \
     --server=https://127.0.0.1:6443 \
     --kubeconfig=${OUT_DIR}/admin.kubeconfig

   kubectl config set-credentials admin \
     --client-certificate=${OUT_DIR}/admin.pem \
     --client-key=${OUT_DIR}/admin-key.pem \
     --embed-certs=true \
     --kubeconfig=${OUT_DIR}/admin.kubeconfig

   kubectl config set-context "${CLUSTER_NAME}" \
     --cluster="${CLUSTER_NAME}" \
     --user=admin \
     --kubeconfig=${OUT_DIR}/admin.kubeconfig

   kubectl config use-context "${CLUSTER_NAME}" --kubeconfig=${OUT_DIR}/admin.kubeconfig
}

#B6
function copy_kubeconfig_workers()
{
  printf "\\n\\nCopying Kube config for worker nodes to worker nodes\\n\\n"

  for w in "${WORKERS_HOSTNAMES[@]}"; do
    scp ${OUT_DIR}/"$w".kubeconfig ${OUT_DIR}/kube-proxy.kubeconfig ${WORKER_USER}@"$w":~/
  done
}

#B7
function copy_kubeconfig_controller()
{
  printf "\\n\\nCopyiing kube configs for controllers to controller nodes\\n\\n"

  for c in "${MASTER_HOSTNAMES[@]}"; do
    scp ${OUT_DIR}/admin.kubeconfig ${OUT_DIR}/kube-controller-manager.kubeconfig ${OUT_DIR}/kube-scheduler.kubeconfig ${CONTROLLER_USER}@"${MASTER_HOSTNAMES[$c]}":~/
  done
}

function clean_up(){
  printf "\\n\\nCleaning up\\n\\n"
  rm ./*.pem 2> /dev/null
  rm ./*.kubeconfig 2> /dev/null
  rm ./*.csr 2> /dev/null
}

function gen_certs(){
gen_ca
sleep 1s
gen_admin_certs
sleep 1s
gen_kubelet_certs
sleep 1s
gen_kube_controller_manager_certs
sleep 1s
gen_kube_proxy_certs
sleep 1s
gen_kube_scheduler_certs
sleep 1s
gen_kube_api_certs
sleep 1s
gen_kube_svc_account_certs
sleep 1s
#copy_worker_certs
#copy_controller_certs

}

function gen_kubeconfigs()
{
  printf "\\n\\nGenerate Kubeconfigs for cluster ${CLUSTER_NAME}\\n\\n"
  gen_kubeconfig_worker
  sleep 1s
  gen_kubeconfig_proxy
  sleep 1s
  gen_kubeconfig_controller
  sleep 1s
  gen_kubeconfig_scheduler
  sleep 1s
  gen_kubeconfig_admin
  sleep 1s
  #copy_kubeconfig_workers
  #copy_kubeconfig_controller
}



gen_certs
gen_kubeconfigs

printf "\\n\\nCompleted\\n\\n"

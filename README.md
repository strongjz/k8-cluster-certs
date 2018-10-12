# k8-cluster-certs
Generates the CA, certs, keys, kubeconfigs for a new cluster

Usage:

Update the IP address and hostnames for your cluster
Run:
```bash
./cert-setup.sh CLUSTER_NAME
```

It will output all the files in the ```output/CLUSTER_NAME``` directory.

Currently does not copy those files to the nesscary servers. 

High level: Cluster setup

https://kubernetes.io/docs/concepts/cluster-administration/certificates/

https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/

A. Generating Certificates

1. Generate the CA configuration file, certificate, and private key
2. Generate a certificate and private key for each Kubernetes worker node:
3. Generate the kube-controller-manager client certificate and private key
4. Generate the kube-proxy client certificate and private key
5. Generate the kube-scheduler client certificate and private key
6. Generate the Kubernetes API Server certificate and private key
7. Generate the service-account certificate and private key
8. ~~Copy the appropriate certificates and private keys to each worker instance~~
9. ~~Copy the appropriate certificates and private keys to each controller instance~~

B. Generate Kube configs

   Generate kubeconfig files for the controller manager, kubelet, kube-proxy, and scheduler clients and the admin user

1. Generate a kubeconfig file for each worker node
2. Generate a kubeconfig file for the kube-proxy service
3. Generate a kubeconfig file for the kube-controller-manager service
4. Generate a kubeconfig file for the kube-scheduler service
5. Generate a kubeconfig file for the admin user
6. ~~Copy the appropriate kubelet and kube-proxy kubeconfig files to each worker instance~~
7. ~~Copy the appropriate kube-controller-manager and kube-scheduler kubeconfig files to each controller instance~~

echo "reminder: run configuration/setup.sh <clientID> <clientSecret> where clientID and clientSecret are the credentials from step 2."
echo "setting up borealis agents using clientIt: $1 and secret: $2"
kubectl create namespace borealis-demo-agent-prod
kubectl create namespace borealis-demo-agent-staging
kubectl create namespace borealis-demo-agent-dev
kubectl create ns borealis-demo-infra
kubectl create ns borealis-dev
kubectl create ns borealis-staging
kubectl create ns borealis-infosec
kubectl create ns borealis-prod
kubectl create ns borealis-prod-eu
kubectl create ns borealis-demo-agent-prod-eu
kubectl create ns borealis-argo
kubectl -n=borealis-demo-agent-prod create secret generic rna-client-credentials --type=string --from-literal=client-secret=$2 --from-literal=client-id=$1
kubectl -n=borealis-demo-agent-staging create secret generic rna-client-credentials --type=string --from-literal=client-secret=$2 --from-literal=client-id=$1
kubectl -n=borealis-demo-agent-dev create secret generic rna-client-credentials --type=string --from-literal=client-secret=$2 --from-literal=client-id=$1
kubectl -n=borealis-demo-agent-prod-eu create secret generic rna-client-credentials --type=string --from-literal=client-secret=$2 --from-literal=client-id=$1


# Optionally Add Armory Chart repo, if you haven't
helm repo add armory https://armory.jfrog.io/artifactory/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# Update repo to fetch latest armory charts
helm repo update
# Install or Upgrade armory rna chart
helm upgrade --install armory-rna-prod armory/remote-network-agent \
    --set clientId='encrypted:k8s!n:rna-client-credentials!k:client-id' \
    --set clientSecret='encrypted:k8s!n:rna-client-credentials!k:client-secret' \
    --set agentIdentifier=demo-prod-west-cluster \
    -n borealis-demo-agent-prod
helm upgrade --install armory-rna-staging armory/remote-network-agent \
    --set clientId='encrypted:k8s!n:rna-client-credentials!k:client-id' \
    --set clientSecret='encrypted:k8s!n:rna-client-credentials!k:client-secret' \
    --set agentIdentifier=demo-staging-cluster \
    -n borealis-demo-agent-staging
helm upgrade --install armory-rna-dev armory/remote-network-agent \
    --set clientId='encrypted:k8s!n:rna-client-credentials!k:client-id' \
    --set clientSecret='encrypted:k8s!n:rna-client-credentials!k:client-secret' \
    --set agentIdentifier=demo-dev-cluster \
    -n borealis-demo-agent-dev
helm upgrade --install armory-rna-prod-eu armory/remote-network-agent \
    --set clientId='encrypted:k8s!n:rna-client-credentials!k:client-id' \
    --set clientSecret='encrypted:k8s!n:rna-client-credentials!k:client-secret' \
    --set agentIdentifier=demo-prod-eu-cluster \
    -n borealis-demo-agent-prod-eu
#helm install prometheus prometheus-community/kube-prometheus-stack -n=borealis-demo-infra --set kube-state-metrics.metricLabelsAllowlist[0]=pods=[*]
#note, this command was needed, but then helm fixed a bug, so now we don't need the quotes.
#helm install prometheus prometheus-community/kube-prometheus-stack -n=borealis-demo-infra --set "kube-state-metrics.metricAnnotationsAllowList[0]=pods=[*]" --set "global.scrape_interval=5s"  --version 30.2.0

sleep 5 #=Adding a timed sleep before prometheus install to see if it resolves some installation issues,
sh argo-rollouts.sh
echo "Attempting Prometheus install"
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n=borealis-demo-infra --set kube-state-metrics.metricAnnotationsAllowList[0]=pods=[*] --set global.scrape_interval=5s --version 35.4.2 --set global.scrape_timeout=1m
BASEDIR=$(dirname $0)
kubectl apply -f "$BASEDIR/../manifests/potato-facts-external-service.yml" -n borealis-prod-eu #Temporary workaround for YODL-300. deploying service along side deployment does not work for Blue/Green.

echo "Installing LinkerD service Mesh on cluster. if you run into errors - see docs at - https://linkerd.io/2.11/getting-started/"
sh linkerd.sh
echo "Adding Linked bin to PATH."
export PATH=~/.linkerd2/bin:$PATH
linkerd check --pre
#linkerd install --crds --set proxyInit.runAsRoot=true --ignore-cluster | kubectl apply -f -
linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -
#curl -sL https://linkerd.github.io/linkerd-smi/install | sh
#linkerd smi install | kubectl apply -f -
echo "LinkerD installation complete, hopefully"
echo "Creating new environment for traffic management deployment"

kubectl create ns borealis-prod-east

kubectl apply -f "$BASEDIR/../manifests/potato-facts-external-service.yml" -n borealis-prod-east

#container_cpu_load_average_10s{namespace="borealis", job="kubelet"} * on (pod)  group_left (label_app) sum(kube_pod_labels{job="kube-state-metrics",label_app="hostname",namespace="borealis"}) by (label_app, pod)

# also tried: --set kube-state-metrics.metricLabelsAllowlist=pods=[*]
# k -n=borealis-demo-infra port-forward service/prometheus-kube-prometheus-prometheus 9090
# example prometheus query for CPU load for pods in a replica set. container_cpu_load_average_10s{name=~"k8s_POD_hostname-5b8bc655f6.+"}

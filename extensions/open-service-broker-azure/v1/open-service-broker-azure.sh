#!/bin/bash
set -x

parameters=$(echo $1 | base64 -d -)

log() {
  echo "`date +'[%Y-%m-%d %H:%M:%S:%N %Z]'` $1"
}

get_param() {
  local param=$1
  echo $(echo "$parameters" | jq ".$param" -r)
}

install_script_dependencies() {
  log ''
  log 'Installing script dependencies'
  log ''

  # Install jq to obtain the input parameters
  log 'Installing jq'
  log ''
  sudo apt-get -y install jq
  log ''

  log 'done'
  log ''
}

cleanup_script_dependencies() {
  log ''
  log 'Removing script dependencies'
  log ''

  log 'Removing jq'
  log ''
  sudo apt-get -y remove jq
  log ''

  log 'done'
  log ''
}

echo $(date) " - Starting Script"

echo $(date) " - Waiting for API Server to start"
kubernetesStarted=1
for i in {1..600}; do
    if [ -e /usr/local/bin/kubectl ]
    then
        /usr/local/bin/kubectl cluster-info
        if [ "$?" = "0" ]
        then
            echo "kubernetes started"
            kubernetesStarted=0
            break
        fi
    else
        /usr/bin/docker ps | grep apiserver
        if [ "$?" = "0" ]
        then
            echo "kubernetes started"
            kubernetesStarted=0
            break
        fi
    fi
    sleep 1
done
if [ $kubernetesStarted -ne 0 ]
then
    echo "kubernetes did not start"
    exit 1
fi

master_nodes() {
    kubectl get no -L kubernetes.io/role -l kubernetes.io/role=master --no-headers -o jsonpath="{.items[*].metadata.name}" | tr " " "\n" | sort | head -n 1
}

wait_for_master_nodes() {
    ATTEMPTS=90
    SLEEP_TIME=10

    ITERATION=0
    while [[ $ITERATION -lt $ATTEMPTS ]]; do
        echo $(date) " - Is kubectl returning master nodes? (attempt $(( $ITERATION + 1 )) of $ATTEMPTS)"

        FIRST_K8S_MASTER=$(master_nodes)

        if [[ -n $FIRST_K8S_MASTER ]]; then
            echo $(date) " - kubectl is returning master nodes"
            return
        fi

        ITERATION=$(( $ITERATION + 1 ))
        sleep $SLEEP_TIME
    done

    echo $(date) " - kubectl failed to return master nodes in the alotted time"
    return 1
}

should_this_node_run_extension() {
    FIRST_K8S_MASTER=$(master_nodes)
    if [[ $FIRST_K8S_MASTER = $(hostname) ]]; then
        echo $(date) " - Local node $(hostname) is found to be the first master node $FIRST_K8S_MASTER"
        return
    else
        echo $(date) " - Local node $(hostname) is not the first master node $FIRST_K8S_MASTER"
        return 1
    fi
}

storageclass_param() {
	kubectl get no -l kubernetes.io/role=agent -l storageprofile=managed --no-headers -o jsonpath="{.items[0].metadata.name}" > /dev/null 2> /dev/null
	if [[ $? -eq 0 ]]; then
		echo '--set redis.persistence.storageClass=managed-standard'
	fi
}

wait_for_tiller() {
    ATTEMPTS=90
    SLEEP_TIME=10

    ITERATION=0
    while [[ $ITERATION -lt $ATTEMPTS ]]; do
        echo $(date) " - Is Helm running? (attempt $(( $ITERATION + 1 )) of $ATTEMPTS)"

        helm version > /dev/null 2> /dev/null

        if [[ $? -eq 0 ]]; then
            echo $(date) " - Helm is running"
            return
        fi

        ITERATION=$(( $ITERATION + 1 ))
        sleep $SLEEP_TIME
    done

    echo $(date) " - Helm failed to start in the alotted time"
    return 1
}

install_helm() {
    echo $(date) " - Downloading helm"
    curl https://storage.googleapis.com/kubernetes-helm/helm-v2.7.2-linux-amd64.tar.gz > helm-v2.7.2-linux-amd64.tar.gz
    tar -zxvf helm-v2.7.2-linux-amd64.tar.gz
    mv linux-amd64/helm /usr/local/bin/helm
    echo $(date) " - Downloading OSBA values"

    curl https://raw.githubusercontent.com/Azure/helm-charts/master/open-service-broker-azure/values.yaml > osba_values.yaml

    curl https://raw.githubusercontent.com/kubernetes-incubator/service-catalog/master/charts/catalog/values.yaml > svccat_values.yaml

    sleep 10

    echo $(date) " - helm version"
    helm version
    helm init

    echo $(date) " - helm installed"
}

add_repos() {
    helm repo add svc-cat https://svc-catalog-charts.storage.googleapis.com
    helm repo add azure https://kubernetescharts.blob.core.windows.net/azure
}

update_helm() {
    echo $(date) " - Updating Helm repositories"
    helm repo update
}

install_svccat() {
    CATALOG_RELEASE_NAME=catalog
    NAMESPACE=$(get_param 'namespace')

    echo $(date) " - Installing the Service Catalog Helm chart"

    helm install -f svccat_values.yaml \
        --name $CATALOG_RELEASE_NAME \
        --namespace $NAMESPACE \
        svc-cat/catalog

    CATALOG_POD_PREFIX="$CATALOG_RELEASE_NAME-catalog-apiserver"
    DESIRED_POD_STATE=Running

    ATTEMPTS=90
    SLEEP_TIME=10

    ITERATION=0
    while [[ $ITERATION -lt $ATTEMPTS ]]; do
        echo $(date) " - Is the catalog api server ($CATALOG_POD_PREFIX-*) running? (attempt $(( $ITERATION + 1 )) of $ATTEMPTS)"

        kubectl get po -n $NAMESPACE --no-headers |
            awk '{print $1 " " $3}' |
            grep $CATALOG_POD_PREFIX |
            grep -q $DESIRED_POD_STATE

        if [[ $? -eq 0 ]]; then
            echo $(date) " - $CATALOG_POD_PREFIX-* is $DESIRED_POD_STATE"
            break
        fi

        ITERATION=$(( $ITERATION + 1 ))
        sleep $SLEEP_TIME
    done
}

install_osba() {
    OSBA_RELEASE_NAME=osba
    NAMESPACE=$(get_param 'namespace')
    AZURE_CLIENT_ID=$(get_param 'clientId')
    AZURE_CLIENT_SECRET=$(get_param 'clientSecret')
    AZURE_SUBSCRIPTION_ID=$(get_param 'subscriptionId')
    AZURE_TENANT_ID=$(get_param 'tenantId')

    echo $(date) " - Installing the OSBA Helm chart"

    helm install -f osba_values.yaml --name $OSBA_RELEASE_NAME --namespace $NAMESPACE \
        --set azure.subscriptionId=$AZURE_SUBSCRIPTION_ID \
        --set azure.tenantId=$AZURE_TENANT_ID \
        --set azure.clientId=$AZURE_CLIENT_ID \
        --set azure.clientSecret=$AZURE_CLIENT_SECRET \
        azure/open-service-broker-azure $(storageclass_param)

    GF_POD_PREFIX="$OSBA_RELEASE_NAME-open-service-broker-azure"
    DESIRED_POD_STATE=Running

    ATTEMPTS=90
    SLEEP_TIME=10

    ITERATION=0
    while [[ $ITERATION -lt $ATTEMPTS ]]; do
        echo $(date) " - Is OSBA api server ($GF_POD_PREFIX-*) running? (attempt $(( $ITERATION + 1 )) of $ATTEMPTS)"

        kubectl get po -n $NAMESPACE --no-headers |
            awk '{print $1 " " $3}' |
            grep $GF_POD_PREFIX |
            grep -q $DESIRED_POD_STATE

        if [[ $? -eq 0 ]]; then
            echo $(date) " - $GF_POD_PREFIX-* is $DESIRED_POD_STATE"
            break
        fi

        ITERATION=$(( $ITERATION + 1 ))
        sleep $SLEEP_TIME
    done
}

ensure_k8s_namespace_exists() {
    NAMESPACE_TO_EXIST=$(get_param 'namespace')

    kubectl get ns $NAMESPACE_TO_EXIST > /dev/null 2> /dev/null
    if [[ $? -ne 0 ]]; then
        echo $(date) " - Creating namespace $NAMESPACE_TO_EXIST"
        kubectl create ns $NAMESPACE_TO_EXIST
    else
        echo $(date) " - Namespace $NAMESPACE_TO_EXIST already exists"
    fi
}

# this extension should only run on a single node
# the logic to decide whether or not this current node
# should run the extension is to alphabetically determine
# if this local machine is the first in the list of master nodes
# if it is, then run the extension. if not, exit
install_script_dependencies
sleep 10
should_this_node_run_extension
if [[ $? -ne 0 ]]; then
    echo $(date) " - Not the first master node, no longer continuing extension. Exiting"
    exit 1
fi

# Deploy container

# the user can pass a non-default namespace through
# extensionParameters as a string. we need to create
# this namespace if it doesn't already exist
if [[ -n $(get_param 'namespace') ]]; then
    NAMESPACE=$(get_param 'namespace')
else
    NAMESPACE=default
fi
ensure_k8s_namespace_exists $NAMESPACE

install_helm
wait_for_tiller
if [[ $? -ne 0 ]]; then
    echo $(date) " - Tiller did not respond in a timely manner. Exiting"
    exit 1
fi
add_repos
update_helm
install_svccat $NAMESPACE
install_osba $NAMESPACE
cleanup_script_dependencies

echo $(date) " - Script complete"

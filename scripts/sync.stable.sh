#!/bin/bash
#descript: GitOps-based CD tool ArgoCD automatic application creation script.

set -eo # Enable pipeline mode, exit on error during execution


# Load utility classes and module scripts
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

function usage(){
    echo "Usage help:"
    echo "The script requires 4 parameters, each separated by space."
    echo "Parameter 1: operation command, has create, sync, delete"
    echo "Parameter 2: repository URL for deployment manifest, CD tool needs to configure authentication and association with this repository beforehand, then obtain resource manifest for deployment."
    echo "Parameter 3: target K8S namespace for deployment application, cloud platform calls it project."
    echo "Parameter 4: CD tool project name, also needs to be configured in CD tool beforehand"
    echo "Parameter 5: deployment environment"
    echo "Parameter 6 (optional) single application deployment name, if parameter 6 is provided, operate only on this single application, otherwise operate on all applications"
    echo "Script parameter example: ./sync.sh create https://gitlab.example.com:deploy/matrix.git matrix-dev matrix-dev dev matrix-view"
}

if [ $# -lt 5 ];then
    usage
    exit 1
fi

# Execute command
CMD=$1
# Git repository containing charts
REPO=$2
# Target namespace for deployment
NAMESPACE=$3
# Default deployment cluster, using cluster short domain name because CD tool is deployed in cluster, can communicate directly with cluster
CLUSTER="${KUBE_CLUSTER:-https://kubernetes.default.svc}"
# CD tool project, this is its classification concept, can classify many applications through one project
ARGO_PROJECT=$4
# Git branch for deployment, referenced through CI variable
BRANCH=${CI_COMMIT_REF_NAME}
# CD naming environment
ARGO_ENV=$5


case ${CMD} in
    create)
    ARGOCD_OPTS="--self-heal --auto-prune --upsert --sync-policy automated  --grpc-web "
    # If parameter 6 is provided, i.e. single application name, operate only on this single application, otherwise operate on all applications
    if [ $6 ];then
        app=$6
        argocd app ${CMD} ${app}-${ARGO_ENV} --repo ${REPO} --path ${app} --dest-namespace ${NAMESPACE} --dest-server ${CLUSTER}  --project ${ARGO_PROJECT} --revision ${BRANCH} ${ARGOCD_OPTS}
    else
        for app in $(ls |grep -Ev 'README|sync.sh|argocd|.gitlab|plottool|turing-ide')
        do
            argocd app ${CMD} ${app}-${ARGO_ENV} --repo ${REPO} --path ${app} --dest-namespace ${NAMESPACE} --dest-server ${CLUSTER}  --project ${ARGO_PROJECT} --revision ${BRANCH} ${ARGOCD_OPTS}
        done
    fi
    ;;
    sync)
    ARGOCD_OPTS="--async --force  --grpc-web "
    # If parameter 6 is provided, i.e. single application name, operate only on this single application, otherwise operate on all applications
    if [ $6 ];then
        app=$6
        argocd app set ${app}-${ARGO_ENV} -p podAnnotations.commitUser=$(date +%Y-%m-%d-%H-%M-%S)  --grpc-web
        argocd app ${CMD} ${app}-${ARGO_ENV} --revision ${BRANCH} ${ARGOCD_OPTS}
    else
        for app in $(ls |grep -Ev 'README|sync.sh|argocd|.gitlab|plottool|turing-ide')
        do
            argocd app set ${app}-${ARGO_ENV} -p podAnnotations.commitUser=$(date +%Y-%m-%d-%H-%M-%S)  --grpc-web
            argocd app ${CMD} ${app}-${ARGO_ENV} --revision ${BRANCH} ${ARGOCD_OPTS}
        done
    fi
    ;;
    delete)
    ARGOCD_OPTS=" --grpc-web "
    # If parameter 6 is provided, i.e. single application name, operate only on this single application, otherwise operate on all applications
    if [ $6 ];then
        app=$6
        argocd app ${CMD} ${app}-${ARGO_ENV} ${ARGOCD_OPTS} || argocd app ${CMD} ${app} ${ARGOCD_OPTS} --cascade=false
    else
        for app in $(ls |grep -Ev 'README|sync.sh|argocd|.gitlab|plottool|turing-ide')
        do
            argocd app ${CMD} ${app}-${ARGO_ENV} ${ARGOCD_OPTS} || argocd app ${CMD} ${app} ${ARGOCD_OPTS} --cascade=false
        done
    fi
    ;;
    *)
    usage
    exit 1;
esac

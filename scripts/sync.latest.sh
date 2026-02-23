#!/bin/bash
#descript: 基于gitops方式CD工具argocd自动创建应用脚本.

set -eo # 表示开启 pipeline 模式，执行期间发生错误，后续步骤多不进行执行。


# 加载 工具类及 模块脚本
for sh in _*.sh
do
  [[ -e "$sh" ]] || break
  source "${sh}"
done

function usage(){
    echo "使用帮助："
    echo "脚本需要提供4个参数,每个参数使用空格隔开."
    echo "第1个参数是操作命令,有create,sync,delete"
    echo "第2个参数是部署清单的仓库,CD工具需要事先配置好跟此仓库进行认证和关联，才能获取到资源清单进行部署." 
    echo "第3个参数是待部署应用的目标K8S命名空间,青云平台上叫项目."
    echo "第4个参数是CD工具划分的项目名称，也需要事先在CD工具上配置好."
    echo "第5个参数是部署环境"
    echo "第6个参数为单个应用的部署名称，如果提供第6个参数，则只单独对此应用做操作，否则对所有应用进行操作（可选项）"
    echo "脚本参数例子： ./sync.sh create https://gitlab.iquantex.com:deploy/matrix.git matrix-dev matrix-dev dev matrix-view"
}

if [ $# -lt 5 ];then
    usage
    exit 1
fi

# 执行命令
CMD=$1
# 存放charts的git仓库
REPO=$2
# 待部署的目标命名空间
NAMESPACE=$3
# 默认部署集群，这里使用集群短域名方式是因为CD工具部署在集群中，可以直接跟集群通讯
CLUSTER="${KUBE_CLUSTER:-https://kubernetes.default.svc}"
# CD工具的项目，这个是它的一个分类概念，可以通过一个项目归类许多应用
ARGO_PROJECT=$4
# 待部署的git分支, 通过CI变量引用分支名
BRANCH=${CI_COMMIT_REF_NAME}
# CD命名环境
ARGO_ENV=$5


case ${CMD} in
    create)
    ARGOCD_OPTS="--self-heal --auto-prune --upsert --sync-policy automated  --grpc-web "
    # 如果提供第6个参数，即单个应用名，则只单独对此应用做操作，否则对所有应用进行操作
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
    # 如果提供第6个参数，即单个应用名，则只单独对此应用做操作，否则对所有应用进行操作
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
    # 如果提供第6个参数，即单个应用名，则只单独对此应用做操作，否则对所有应用进行操作
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

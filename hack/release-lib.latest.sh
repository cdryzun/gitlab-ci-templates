if [ ${REMOTE_BRANCH} = 'prd' ];then
    git restore pom.xml && mvn -B release:prepare -DtagNameFormat=@{project.version} \
    -DreleaseVersion=${DOCKER_IMAGE_TAG} -DpushChanges=false -DlocalCheckout=true -Dmaven.test.skip=true -T $(nproc) && mvn release:perform \
    -Darguments='-Dmaven.javadoc.skip=true' -Dmaven.test.skip=true -DlocalCheckout=true \
    -T $(nproc)
elif [ "${CI_COMMIT_BRANCH}" = "${CI_DEFAULT_BRANCH}" ];then
    if [ "${SNAPSHOTS_LIB_BUILD}" == 'true' ];then
        mvn clean deploy -Dmaven.test.skip=true
    else
        exit 0
    fi
fi
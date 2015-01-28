isValidVersion(){
    local  version=$1
    local  stat=1
    if [[ $version =~ ^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
        OIFS=$IFS
        IFS='.'
        version=($version)
        IFS=$OIFS
        [[ ${version[0]} -le 100 && \
           ${version[1]} -le 100 && \
           ${version[2]} -le 100 ]]
        stat=$?
    fi
    return $stat
}

pr(){

 SCM_COMMENT_PREFIX="[release]"
 STABLE_VERSION="1.0.3"
 CURRENT_VERSION="${STABLE_VERSION}-SNAPSHOT"
 _USER_VERSION=$1
 if [ "${_USER_VERSION}" = "" ];then
   STABLE_VERSION="1.0.3"
 else
   if isValidVersion ${_USER_VERSION}; then
    STABLE_VERSION=${_USER_VERSION}
   else
    echo "The provided is invalid. It must match [Major].[Minor].[Increment]" && exit 1
   fi
 fi
 echo $STABLE_VERSION
}
USER_IN=$1
pr $USER_IN
#pwd
#ls
#echo Hello

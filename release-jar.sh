#!/bin/bash

#[ "$DO_RELEASE" != "true" ] && exit 0

SELF=$(basename $0)
MASTER=master
DEV=develop
RELEASE=release
HOTFIX=hotfix
GIT=/opt/gitlab/embedded/bin/git
MAVEN=/opt/apache-maven-3.2.5/bin/mvn
# LQ
MAVEN=/data/apps/maven/bin/mvn
GREP=grep

# The most important line in each script
set -e

# Check for the git command
command -v ${GIT} >/dev/null || {
    echo "$SELF: ${GIT} command not found." 1>&2
    exit 1
}
# Check for the mvn command (maven)
command -v ${MAVEN} >/dev/null || {
    echo "$SELF: ${MAVEN} command not found." 1>&2
    exit 1
}

get_release_branch() {
    echo "${RELEASE}/$1"
}

create_release_branch() {
    echo -n "Creating release branch... "
    RELEASE_BRANCH=$(get_release_branch $1)
    echo "$RELEASE_BRANCH"
    create_branch=$(${GIT} checkout -b ${RELEASE_BRANCH} ${DEV} 2>&1)
}

remove_release_branch() {
    echo -n "Removing release branch... "
    RELEASE_BRANCH=$(get_release_branch $1)
    echo "$RELEASE_BRANCH"
    remove_branch=$(${GIT} branch -D ${RELEASE_BRANCH} 2>&1)
}

mvn_release() {

    #echo "Releasing project"
    MVN_USER_VERSION=$1
    MVN_RELEASE_PREPARE_ARGS="-DpushChanges=false -DtagNameFormat=@{project.version} "
    [ "${MVN_USER_VERSION}" != "" ] && MVN_RELEASE_PREPARE_ARGS="$MVN_RELEASE_PREPARE_ARGS -DreleaseVersion=${MVN_USER_VERSION}"
    # -DdevelopmentVersion=${MVN_USER_VERSION}-SNAPSHOT" 
    MVN_RELEASE_PERFORM_ARGS="-DlocalCheckout=true "
    #-Dgoals=install -Drepo.url=http://localhost:8081/nexus"
    MVN_DEBUG_RELEASE=true
    # Phase release:prepare cree 2 commits dans le repo local : 
    # Commit 1 # Change la version du pom (enleve -SNAPSHOT) et ajoute le nom du tag dans la section scm connection du pom.xml
    # Creation d'un tag dans le repo local
    # Commit 2 # Change la version du pom vers le prochain snapshot  (ajoute snapshot version-prochaine-SNAPSHOT ) and supprime  le nom du tag dans scm connection details.
    # Phase release:perform : Build du code qui porte le tag et exectuion du goal -Dgoals=package ou (deploy par defaut = upload dans Nexus). Penser a mettre site-deploy
    if [ "${MVN_DEBUG_RELEASE}" = "true" ] ; then
       #echo "${MAVEN} $MVN_ARGS ${MVN_RELEASE_PREPARE_ARGS} -B release:prepare"
       #echo "${MAVEN} $MVN_ARGS ${MVN_RELEASE_PERFORM_ARGS} release:perform"
       #exit  
       ${MAVEN} $MVN_ARGS ${MVN_RELEASE_PREPARE_ARGS} -B release:prepare
       ${MAVEN} $MVN_ARGS ${MVN_RELEASE_PERFORM_ARGS} release:perform
    else
       echo -n "Using maven-release-plugin... "
       mvn_release_prepare=$(${MAVEN} ${MVN_ARGS} ${MVN_RELEASE_PREPARE_ARGS} -B release:prepare)
       echo -n "'mvn -B release:prepare' "
       mvn_release_perform=$(${MAVEN} ${MVN_ARGS} ${MVN_RELEASE_PERFORM_ARGS} release:perform)
       echo "'mvn release:perform'"
    fi
}

# Merging the content of release branch to develop
merging_to_develop() {
    echo -n "Merging back to ${DEV}... "
    RELEASE_BRANCH=$(get_release_branch $1)
    git_co_develop=$(${GIT} checkout ${DEV} 2>&1)
    git_merge=$(${GIT} merge --no-ff -m "${SCM_COMMENT_PREFIX}merge ${RELEASE_BRANCH} into ${DEV}" ${RELEASE_BRANCH} 2>&1)
    echo "done"
}

# Rewind 1 commit (tag)
# Merge master in release_branch with ours strategy (we have the sure one)
# Merge back release_branch to master
merging_to_master() {
    echo -n "Merging back to ${MASTER}... "
    RELEASE_BRANCH=$(get_release_branch $1)
    git_co_release_branch=$(${GIT} checkout ${RELEASE_BRANCH} 2>&1)
    git_resete_release_branch=$(${GIT} reset --hard HEAD~1)
    git_merge_ours=$(${GIT} merge -s ours -m "${SCM_COMMENT_PREFIX}merge ${MASTER} into ${RELEASE_BRANCH}"  ${MASTER} 2>&1)
    git_co_master=$(${GIT} checkout ${MASTER} 2>&1)
    # We make the assumption "theirs" is the best
    git_merge=$(${GIT} merge --no-ff -m "${SCM_COMMENT_PREFIX}merge ${RELEASE_BRANCH} into ${MASTER}" ${RELEASE_BRANCH} 2>&1)
    echo "done"
}

track_remote_branch(){

  local _BRANCH=$1
  if ! ${GIT} branch|${GREP} -wq ${_BRANCH}; then
    echo -n "Creating a local branch ${_BRANCH} to track origin/${_BRANCH}... "
    track_branch=$(${GIT} branch --track ${_BRANCH} origin/${_BRANCH} 2>&1)
    echo "done"
  else
    echo "Branch ${_BRANCH} is already tracked."
  fi
}

# push changes to server
push_changes (){
    echo -n "Pushing changes to server... "
    git_push_changes=$(${GIT} push --all && ${GIT} push --tags 2>&1)
    echo "done"
}

# checkout
checkout_branch (){
    local _BRANCH=$1
    #echo -n "Checking out branch ${_BRANCH}... "
    git_co=$(${GIT} checkout ${_BRANCH} 2>&1)
    #echo "done"
}

assert_tag_version_exist(){

    _RELEASE=$1
    echo "${GIT} show-ref --verify --quiet refs/tags/${_RELEASE}"
    ${GIT} show-ref --verify --quiet "refs/tags/${_RELEASE}"
    if [ $? -eq 0 ]; then
      echo "fatal - A local tag already exist tags/${_RELEASE}."
      echo "[###] Released ${_RELEASE} [FAILED]"
      exit 1
    fi
    echo iiiii
    ${GIT} ls-remote --exit-code . "tags/${_RELEASE}" &> /dev/null
    if [ $? -eq 0 ]; then
      echo "fatal - A remote tag already exist tags/${_RELEASE}."
      echo "[###] Released ${_RELEASE} [FAILED]"
      exit 1
    fi
}

get_dev_version(){
 if $(${GIT} rev-parse 2>/dev/null); then
    BRANCH_NAME=$(${GIT} symbolic-ref -q HEAD)
    BRANCH_NAME=${BRANCH_NAME##refs/heads/}
    WORKING_DIR=$(${GIT} rev-parse --show-toplevel)
    cd $WORKING_DIR
    checkout_branch ${DEV}
    CURRENT_VERSION=$(${MAVEN} ${MVN_ARGS} org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version | sed -n -e '/Down.*/ d' -e '/^\[.*\]/ !{ /^[0-9]/ { p; q } }')
    checkout_branch $BRANCH_NAME
    if test "$CURRENT_VERSION" = "${CURRENT_VERSION%-SNAPSHOT}"; then
        echo "$SELF: version '${CURRENT_VERSION}' specified is not a snapshot"
        exit 1
    else
        STABLE_VERSION="${CURRENT_VERSION%-SNAPSHOT}"
        echo $STABLE_VERSION
    fi
 else
    echo "$SELF: you are not in a git directory"
    exit 1
 fi

}


get_version(){

 # First get the working directory
 test -n "$MVN_ARGS" && {
    echo "Maven arguments provided : $MVN_ARGS."
 }
 #echo -n "Detecting version number... "
 if $(${GIT} rev-parse 2>/dev/null); then
    BRANCH_NAME=$(${GIT} symbolic-ref -q HEAD)
    BRANCH_NAME=${BRANCH_NAME##refs/heads/}
    WORKING_DIR=$(${GIT} rev-parse --show-toplevel)
    cd $WORKING_DIR
    checkout_branch $MASTER
    STABLE_VERSION=$(${MAVEN} ${MVN_ARGS} org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version | sed -n -e '/Down.*/ d' -e '/^\[.*\]/ !{ /^[0-9]/ { p; q } }')
    checkout_branch $BRANCH_NAME
    echo $STABLE_VERSION
 else
    echo "$SELF: you are not in a git directory"
    exit 1
 fi

}

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

release(){

 echo "Releasing Maven Project : ${POM_GROUPID}:${POM_ARTIFACTID}"
 SCM_COMMENT_PREFIX="[release]"
 local _USER_VERSION=$1
 STABLE_VERSION=$(get_dev_version)
 CURRENT_VERSION="${STABLE_VERSION}-SNAPSHOT"
 if [ "${_USER_VERSION}" != "" ];then
    DEV_VERSION=${STABLE_VERSION}
    STABLE_VERSION=${_USER_VERSION}
 fi
 #CURRENT_VERSION="${STABLE_VERSION}-SNAPSHOT"
 echo "--------------------------------------------------"
 echo " Release branch $DEV $CURRENT_VERSION to $STABLE_VERSION "
 echo "--------------------------------------------------"
 #assert_tag_version_exist $STABLE_VERSION
 track_remote_branch ${MASTER}
 track_remote_branch ${DEV}
 create_release_branch $STABLE_VERSION
 mvn_release $STABLE_VERSION
 merging_to_develop $STABLE_VERSION
 merging_to_master $STABLE_VERSION
 remove_release_branch $STABLE_VERSION
 checkout_branch $BRANCH_NAME
 echo "Next step : deploy the application in TA (webapp)"
 #touch doPostRelease
 push_changes
}

USER_VERSION=$1

if [ "${USER_VERSION}" != "" ];then 
 if ! isValidVersion ${USER_VERSION}; then
   echo "La version choisie est invalids. Elle doit correspondre au motif suivant: [Major].[Minor].[Increment] " && exit 1
 fi
fi
release ${USER_VERSION}


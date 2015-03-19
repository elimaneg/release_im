#!/bin/bash

#[ "$DO_RELEASE" != "true" ] && exit 0
# args
# 1: jar|webapp
# 2: stage|post
# 3: version

# jar : one shot
# webapp :
#       1. mvn release:stage => les artefacts sont deployes dans le repo PreRelease
#       2. Deploiement des artefacts depuis PreRelease vers TA + tests. si KO : supprimer tag/branche (releease/version) et peut etre artefact dans PreRelease (sinon ecrase par la prochaine tentative de release)
#       3. Mise a jour des branches master et develop + deplacement des artefact de Prerelease vers Release

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
MVN_DEBUG_RELEASE=true

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

mvn_stage() {

    MVN_USER_VERSION=$2
    MVN_RELEASE_STAGING_REPOSITORY=$1
    MVN_RELEASE_STAGE_ARGS="-DpushChanges=false -DtagNameFormat=@{project.version} -DstagingRepository="${MVN_RELEASE_STAGING_REPOSITORY}""
    [ "${MVN_USER_VERSION}" != "" ] && MVN_RELEASE_STAGE_ARGS="$MVN_RELEASE_PREPARE_ARGS -DreleaseVersion=${MVN_USER_VERSION}"
    MVN_RELEASE_PERFORM_ARGS="-DlocalCheckout=true -Dgoals=deploy"
    ${MAVEN} $MVN_ARGS ${MVN_RELEASE_STAGE_ARGS} -B release:stage && \
    ${MAVEN} $MVN_ARGS ${MVN_RELEASE_PERFORM_ARGS} release:perform
    #echo -n "Staging release with maven-release-plugin... "
    #mvn_release_staging=$(${MAVEN} ${MVN_ARGS} ${MVN_RELEASE_PREPARE_ARGS} -B release:stage && \
    #${MAVEN} ${MVN_ARGS} ${MVN_RELEASE_PERFORM_ARGS} release:perform)
    #echo "Maven stage-release done"
    #fi
}


mvn_release() {

    MVN_USER_VERSION=$1
    MVN_RELEASE_PREPARE_ARGS="-DpushChanges=false -DtagNameFormat=@{project.version} "
    [ "${MVN_USER_VERSION}" != "" ] && MVN_RELEASE_PREPARE_ARGS="$MVN_RELEASE_PREPARE_ARGS -DreleaseVersion=${MVN_USER_VERSION}"
    MVN_RELEASE_PERFORM_ARGS="-DlocalCheckout=true -Dgoals=deploy"
    # Phase release:prepare cree 2 commits dans le repo local : 
    # Commit 1 # Change la version du pom (enleve -SNAPSHOT) et ajoute le nom du tag dans la section scm connection du pom.xml
    # Creation d'un tag dans le repo local
    # Commit 2 # Change la version du pom vers le prochain snapshot  (ajoute snapshot version-prochaine-SNAPSHOT ) and supprime  le nom du tag dans scm connection details.
    # Phase release:perform : Build du code qui porte le tag et exectuion du goal -Dgoals=package ou (deploy par defaut = upload dans Nexus). Penser a mettre site-deploy
    #if [ "${MVN_DEBUG_RELEASE}" = "true" ] ; then
       ${MAVEN} $MVN_ARGS ${MVN_RELEASE_PREPARE_ARGS} -B release:prepare && \
       ${MAVEN} $MVN_ARGS ${MVN_RELEASE_PERFORM_ARGS} release:perform
    #else
    #   echo -n "Using maven-release-plugin... "
    #   mvn_release_prepare=$(${MAVEN} ${MVN_ARGS} ${MVN_RELEASE_PREPARE_ARGS} -B release:prepare && \ 
    #   ${MAVEN} ${MVN_ARGS} ${MVN_RELEASE_PERFORM_ARGS} release:perform)
    #   echo "'mvn release:perform'"
    #fi
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

isValidGitRepo(){
    local  repo=$1
    local  stat=1
    ${GIT}  ls-remote $repo |grep HEAD
    stat=$?
    return $stat
}

post_release(){

 echo "Execution de la Post-implantation du projet : ${POM_GROUPID}:${POM_ARTIFACTID}"
 if [ ! doPostRelease ] ;then
  echo "Le code source differe de celui sur lequel la phase de pre-release a été effectuées. Recommencez le release"
  exit 1
 else
  echo "Mise a jour des branches master et develop sur le serveur git"
  #push_changesa
  echo "Deplacement de artefacts de Pre-release vers Release"
 fi
}

release(){
 #webapp stage ${_RELEASE_VERSION}
 echo "Execution de la realisation Maven Project : ${POM_GROUPID}:${POM_ARTIFACTID}"
 SCM_COMMENT_PREFIX="[release]"
 local _ATYPE=$1 # jar
 local _RTYPE=$2 # stage or post
 local _USER_VERSION=$3
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
 if [ "${_RTYPE}" = "stage" ]; then 
   mvn_stage ${_STAGING_REPO} $STABLE_VERSION
 else
   mvn_release $STABLE_VERSION 
 fi
 merging_to_develop $STABLE_VERSION
 merging_to_master $STABLE_VERSION
 remove_release_branch $STABLE_VERSION
 checkout_branch $BRANCH_NAME
 if [ "${_ATYPE}" = "jar" ]; then
  # jar
  push_changes
 else
  # webapp
  echo "Prochaine etape : deployer l'application en TA (webapp) a partir du repository Nexus Pre-release"
  touch doPostRelease
 fi
}

# defaults
_STAGING_REPO=PreRelease

while getopts ":a:t:r:v:" opt; do
  case $opt in
    t)
      _RELEASE_ARTIFACT=$OPTARG # 1: jar|webapp
      [ "${_RELEASE_ARTIFACT}" != "jar" -a "${_RELEASE_ARTIFACT}" != "webapp" ] && \
      echo "Option -t (type d'artefact), Valeurs possibles : jar|webapp " && exit 1
      ;;
    a)
      _RELEASE_TYPE=$OPTARG # stage|post
      if [ "${_RELEASE_TYPE}" != "stage" -a "${_RELEASE_TYPE}" != "post" ] ; then
      echo -n -e "Option -a (requise quand le projet est de type webapp) , valeurs possibles : stage|post \n - stage : deployer les artefacts dans PreReleases pour test en TA \
      \n - post : mettre a jour les branches master et develop et deplacer les artefacts de PreReleases vers Releases\n" && exit 1
      fi
      ;;
    v)
      _RELEASE_VERSION=$OPTARG # version
      if [ "${_RELEASE_VERSION}" != "" ];then
        if ! isValidVersion ${_RELEASE_VERSION}; then
          echo "La version specifiée est invalide. Elle doit respecter le patron : [Major].[Minor].[Increment] " && exit 1
        fi
      fi
      ;;
    d)
      _RELEASE_GIT_REPOS=$OPTARG # depot git
      if [ "${_RELEASE_GIT_REPOS}" != "" ];then
        if ! isValidGitRepo ${_RELEASE_GIT_REPOS}; then
          echo "Le depot git est inaccessible. verifier la saisie : git@gitlab.loto-quebec.com:GROUPE/PROJET.git " && exit 1
        fi
      fi
      ;;
    r)
      _STAGING_REPO=$OPTARG # repo of the release
      ;;
    \?)
      echo "Option invalide: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "L'option -$OPTARG requiert un argument." >&2
      exit 1
      ;;
  esac
done

if [ "${_RELEASE_ARTIFACT}" = "" ] ;then 
 echo "L'option -t est obligatoire" && exit 1
else
 case ${_RELEASE_ARTIFACT} in
    # release jar (one shot = les autres options sont inutiles)
    jar) echo "release jar ${_RELEASE_VERSION}"
         ;;
    webapp)
         if [ "${_RELEASE_TYPE}" = "" ] ; then 
           echo "L'option -a devient obligatoire quand l'option -t est presente" && $0 -t webapp -a xxx && exit 1
         else
	   case ${_RELEASE_TYPE} in
	     post) echo post_release ;;
	     stage) echo "release webapp stage ${_STAGING_REPO} ${_RELEASE_VERSION}";;
           esac
         fi
	;;
 esac
fi

function clone_repo(){
 local _GIT_REPO=$1
 local _WS=${WORKSPACE}
 if [ "${_WS}" = "" ] then 
  _WS=$(mktemp -d)
  _WIPE_IT_LATER=${_WS}
 else
  find ${_WS} -name . -o -prune -exec rm -fr -- {} + 
 fi
 ${GIT} clone ${_GIT_REPO} "${_WS}"
}


 [ -d ${_WIPE_IT_LATER} ] && echo "echo dont forget to delete "${_WIPE_IT_LATER}" if out of Jenkins"

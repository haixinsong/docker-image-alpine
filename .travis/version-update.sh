#!/usr/bin/env bash

MIRRORS=https://mirrors.tuna.tsinghua.edu.cn/alpine
GIT_USERNAME=nediiii
GIT_USEREMAIL=varnediiii@gmail.com
GIT_REPONAME=docker-image-alpine
DOCKER_USERNAME=nediiii
DOCKER_REPONAME=alpine

timelog() {
  echo $(date '+%F %T'): $@
}

# only alpinelniux 3.5 and newer will release minirootfs package
# parameter: version number with "x.x" formated
# if version number >= 3.5 return 1 , otherwise return 0
versionCompatible() {
  if [[ $# -eq 1 ]]; then
    the_major_version=$(echo $1 | cut -d '.' -f1)
    the_minor_version=$(echo $1 | cut -d '.' -f2)
    if [[ $the_major_version < 3 ]]; then
      return 0
    fi
    if [[ $the_major_version -gt 3 ]]; then
      return 1
    fi
    if [[ $the_major_version -eq 3 ]]; then
      if [[ $the_minor_version -ge 5 ]]; then
        return 1
      else
        return 0
      fi
    fi
  fi
}

setup_git() {
  git config --global user.name "$GIT_USERNAME"
  git config --global user.email "$GIT_USEREMAIL"
  mkdir ~/workdir
  cd ~/workdir
  git clone https://${GH_TOKEN}@github.com/$GIT_USERNAME/$GIT_REPONAME.git $GIT_USERNAME/$GIT_REPONAME >/dev/null 2>&1
  cd $GIT_USERNAME/$GIT_REPONAME
  # track all branch locally
  git branch -r | grep -v '\->' | while read remote; do git branch --track "${remote#origin/}" "$remote"; done
  git fetch --all
  git pull --all
}

# prevent multi tag commit in a short period,
# like push more than 10 tags in an hour
avoid_rapid_tag() {
  LATEST_TAG_NAME=$(git describe --abbrev=0)
  if [[ -n $LATEST_TAG_NAME ]]; then
    # already has a tag
    # then check the tag commit time
    LATEST_COMMIT_TIME_IN_SECONDS=$(git log -1 --format=%at $LATEST_TAG_NAME)
    NOW_TIME_IN_SECONDS=$(date +%s)
    THREE_HOURS_AFTER_TAG_IN_SECONDS=$((LATEST_COMMIT_TIME_IN_SECONDS + 3 * 60 * 60))
    if [[ NOW_TIME_IN_SECONDS -lt THREE_HOURS_AFTER_TAG_IN_SECONDS ]]; then
      timelog "prevent multi tag commit in a short period, this build is aborted"
      exit 0
    fi
  fi
  timelog "not tag yet, ready to build"
}

push_to_github() {
  git push --all --follow-tags --atomic --quiet
}

update_version() {
  avoid_rapid_tag
  # VERSIONS_ARR=($(cat test.html | grep 'released.html' | cut -d '-' -f4 | sort -V))
  VERSIONS_ARR=($(curl 'https://alpinelinux.org/posts/' | grep 'released.html' | cut -d '-' -f4 | sort -V))
  # update alpinelinux version
  echo ===================================================================================

  # docker hub only contain 10 tag to auto build queue,
  # if you push 11 tags in a short time,
  # it will not auto build the last one tag.
  DOCKER_HUB_AUTOBUILD_QUEUE_MAX=10
  AUTOBUILD_QUEUE_COUNT=0
  for i in "${VERSIONS_ARR[@]}"; do
    if [[ AUTOBUILD_QUEUE_COUNT -lt DOCKER_HUB_AUTOBUILD_QUEUE_MAX ]]; then
      MAJOR_VERSION=$(echo $i | cut -d '.' -f1-2) # eg. 3.10  in 3.10.2
      MINOR_VERSION=$(echo $i | cut -d '.' -f3)   # eg. 2     in 3.10.2

      versionCompatible $MAJOR_VERSION
      if [[ $? -eq 1 ]] && [[ -z $(cat version.txt | grep $i) ]]; then
        # update version number in Dockerfile
        sed -i "s#MAJOR_VERSION=[[:digit:]]\+.[[:digit:]]\+#MAJOR_VERSION=$MAJOR_VERSION#" Dockerfile                                                                                # update major version number, like 3.5 in 3.5.1
        sed -i "s#MINOR_VERSION=[[:digit:]]\+#MINOR_VERSION=$MINOR_VERSION#" Dockerfile                                                                                              # update minor version number, like 1 in 3.5.1
        sed -i "/docker build . --no-cache/c\# docker build . --no-cache -t $DOCKER_USERNAME\/$DOCKER_REPONAME:${MAJOR_VERSION} -t $DOCKER_USERNAME\/$DOCKER_REPONAME:$i" Dockerfile # update comment line in the bottom
        if [[ -z $(cat README.md | grep ${MAJOR_VERSION}) ]]; then
          # add a new line after line 9
          sed -i "11a - [${MAJOR_VERSION}.${MINOR_VERSION}, ${MAJOR_VERSION}](https://github.com/$GIT_USERNAME/$GIT_REPONAME/blob/v${MAJOR_VERSION}.${MINOR_VERSION}/Dockerfile)" README.md
        else
          sed -i "/${MAJOR_VERSION}/c- [${MAJOR_VERSION}.${MINOR_VERSION}, ${MAJOR_VERSION}](https://github.com/$GIT_USERNAME/$GIT_REPONAME/blob/${MAJOR_VERSION}.${MINOR_VERSION}/Dockerfile)" README.md
        fi
        versiontxt=$(cat version.txt)
        echo $i >>version.txt
        git add .
        git commit -m "${MAJOR_VERSION}.${MINOR_VERSION} updated"
        if [[ -z $(echo $versiontxt | grep ${MAJOR_VERSION}) ]]; then
          git checkout --orphan v${MAJOR_VERSION}
          git rm --cached -r .
          rm -rf * .travis.yml .travis >/dev/null 2>&1
        else
          git checkout v${MAJOR_VERSION}
        fi
        git checkout master -- Dockerfile
        git checkout master -- README.md
        git add .
        git commit -m "${MAJOR_VERSION}.${MINOR_VERSION} updated"

        git checkout master
        git tag -a -m "${MAJOR_VERSION}.${MINOR_VERSION} updated" v${MAJOR_VERSION}.${MINOR_VERSION}

        push_to_github

        AUTOBUILD_QUEUE_COUNT=$((AUTOBUILD_QUEUE_COUNT + 1))

        echo -----------------------------------------------------------------------------------
      fi
    fi
  done
  echo ===================================================================================
}

setup_git
update_version

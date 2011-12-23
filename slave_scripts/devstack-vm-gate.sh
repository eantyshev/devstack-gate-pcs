#!/bin/bash -x

# Gate commits to several projects on a VM running those projects
# configured by devstack.

# Copyright (C) 2011 OpenStack LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

HOSTNAME=devstack-$GERRIT_CHANGE_NUMBER-$GERRIT_PATCHSET_NUMBER-$BUILD_NUMBER.slave.openstack.org
PROJECTS="openstack/nova openstack/glance openstack/keystone openstack/python-novaclient openstack-dev/devstack openstack/openstack-ci"

# Set this to 1 to always keep the host around
ALWAYS_KEEP=${ALWAYS_KEEP:-0}

CI_SCRIPT_DIR=$(cd $(dirname "$0") && pwd)
cd $WORKSPACE

for PROJECT in $PROJECTS
do
    echo "Setting up $PROJECT"
    SHORT_PROJECT=`basename $PROJECT`
    if [[ ! -e $SHORT_PROJECT ]]; then
	echo "  Need to clone"
	git clone https://review.openstack.org/p/$PROJECT
    fi
    cd $SHORT_PROJECT
    
    BRANCH=$GERRIT_BRANCH

    # See if this project has this branch, if not, use master
    git remote update
    if ! git branch -a |grep remotes/origin/$GERRIT_BRANCH>/dev/null; then
	BRANCH=master
    fi
    git reset --hard
    git clean -x -f
    git checkout $BRANCH
    git reset --hard remotes/origin/$BRANCH
    git clean -x -f

    if [[ $GERRIT_PROJECT == $PROJECT ]]; then
	echo "  Merging proposed change"
	git fetch https://review.openstack.org/p/$PROJECT $GERRIT_REFSPEC
	git merge FETCH_HEAD
    else
	echo "  Updating from origin"
	git pull --ff-only origin $BRANCH
    fi
    cd $WORKSPACE
done

eval `python $CI_SCRIPT_DIR/devstack-vm-fetch.py` || exit $?

scp -C $CI_SCRIPT_DIR/devstack-vm-gate-host.sh $NODE_IP_ADDR:
RETVAL=$?
if [ $RETVAL != 0 ]; then
    echo "Deleting host"
    python $CI_SCRIPT_DIR/devstack-vm-delete.py $NODE_UUID
fi

scp -C -q -r $WORKSPACE/ $NODE_IP_ADDR:workspace
RETVAL=$?
if [ $RETVAL != 0 ]; then
    echo "Deleting host"
    python $CI_SCRIPT_DIR/devstack-vm-delete.py $NODE_UUID
fi

ssh $NODE_IP_ADDR ./devstack-vm-gate-host.sh
RETVAL=$?
if [ $RETVAL = 0 ] && [ $ALWAYS_KEEP = 0 ]; then
    echo "Deleting host"
    python $CI_SCRIPT_DIR/devstack-vm-delete.py $NODE_UUID
else
    #echo "Giving host to developer"
    #python $CI_SCRIPT_DIR/devstack-vm-give.py $NODE_UUID
    exit $RETVAL
fi
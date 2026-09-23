#!/bin/bash
#
# Copyright (C) 2022-2023 The LeafOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

usage() {
    echo "Usage ${0} <branch>"
}

# Verify argument count
if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

BRANCH="${1}"

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo "Must be run from the top level repo dir"
    exit 1
fi

# Source build environment (needed for gettop)
. build/envsetup.sh

TOP="$(gettop)"
MERGEDREPOS="${TOP}/merged_repos_lmo.txt"
FROSTY_BRANCH=$(git -C ${TOP}/.repo/manifests.git config --get branch.default.merge | sed 's#refs/heads/##g')

repo forall -g lmo -c 'git pull frosty ananas --unshallow'

# Build list of Revived forked repos
PROJECTPATHS=$(repo forall -g lmo -c 'echo -n "$REPO_PATH "')

echo "#### Frosty branch = ${BRANCH} Branch = ${FROSTY_BRANCH} ####"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on Frosty forked LMODroid projects ####"
for PROJECTPATH in ${PROJECTPATHS} .repo/manifests; do
    # Skip fully removed projects
    [ ! -d "${TOP}/$PROJECTPATH" ] && continue;
    cd "${TOP}/${PROJECTPATH}"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Path ${PROJECTPATH} has uncommitted changes. Please fix."
        exit 1
    fi
done
echo "#### Verification complete - no uncommitted changes found ####"

# Remove any existing list of merged repos file
rm -f "${MERGEDREPOS}"

# Iterate over each forked project
for PROJECTPATH in ${PROJECTPATHS}; do
    REPO=platform_$(echo $PROJECTPATH | sed 's|/|_|g')
    REPOBRANCH="${BRANCH}"
    LOCAL_BRANCH="${FROSTY_BRANCH}"

    cd "${TOP}/${PROJECTPATH}"
    echo "### Merging ${REPOBRANCH} into ${PROJECTPATH} ###"
    git fetch https://github.com/LMODroid/"${REPO}" "${REPOBRANCH}"

    # Was there any change upstream? Skip if not.
    if [[ -z "$(git log --oneline HEAD..FETCH_HEAD)" ]]; then
        echo -e "nochange\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        continue
    fi

    git merge FETCH_HEAD --into-name "${LOCAL_BRANCH}"

    CONFLICT=""
    if [[ -n "$(git status --porcelain)" ]]; then
        echo -e "conflict-merge\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
    else
        echo -e "merge\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
    fi
done

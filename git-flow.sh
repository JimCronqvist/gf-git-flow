#/bin/bash

#
# gf - Git flow based
# Wrapper which adds some functionality
#
# Copyright 2017 Jim Cronqvist (jim.cronqvist@gmail.com). All rights reserved.
#
# @See: http://nvie.com/posts/a-successful-git-branching-model/
# @See: https://github.com/nvie/gitflow
#


# Common functions
die() { 
    echo "$@" >&2; 
    exit 1;
}

git_require_this_script_init() {
    PREFIX=$(git config --get gitflow.prefix.feature)
    if [ "$PREFIX" != "feature/" ]; then
        die "Please initialize this script by running 'bash git-flow.sh init'"
    fi
}

git_require_git_repo_dir() {
    if ! test -d $(pwd)"/.git/" ; then
        die "You are not in a GIT repo. Aborting."
    fi
}

startswith() { 
    [ "$1" != "${1#$2}" ]; 
}

git_current_branch() {
    git branch --no-color | grep '^\*' | grep -v 'no branch' | sed 's/^* //g'
}

git_get_version_from_branch_name() {
    echo $NAME | sed 's/[^0-9\.]*//g'
}

git_is_clean_working_tree() {
    if ! git diff --no-ext-diff --ignore-submodules --quiet --exit-code; then
        return 1
    elif ! git diff-index --cached --quiet --ignore-submodules HEAD --; then
        return 2
    else
        return 0
    fi
}

git_require_clean_working_tree() {
    if test -f ./.git/MERGE_HEAD ; then
        die "fatal: Working tree contains unresolved merge conflicts. Hint: To abort run 'git merge --abort'"		
    fi
    git_is_clean_working_tree
    local result=$?
    if [ $result -eq 1 ]; then
        die "fatal: Working tree contains unstaged changes. Aborting."
    fi
    if [ $result -eq 2 ]; then
        die "fatal: Index contains uncommited changes. Aborting."
    fi
}

git_pull_develop() {
    local CURRENT_BRANCH=$(git_current_branch)
    if [ "$CURRENT_BRANCH" != "$DEVELOP_BRANCH" ]; then
        git checkout $DEVELOP_BRANCH
    fi
    if git rev-parse --symbolic-full-name @{u} 2>&1 | grep -v 'no upstream configured for branch' -q ; then
        git pull
    fi
    if [ "$CURRENT_BRANCH" != "$(git_current_branch)" ]; then
        git checkout $CURRENT_BRANCH
    fi
}


# Arguments
SUBCMD=$1
ACTION=$2
NAME=$3

# Define the different branches
CURRENT_BRANCH=$(git_current_branch)
DEVELOP_BRANCH="develop"
MASTER_BRANCH="master"
VERSION_FILE="version.txt"


# Ensure that the branch prefix is there
if [ "$SUBCMD" == "feature" ]; then
    # Prepend the feature prefix to the branch name if not provided
    PREFIX=$(git config --get gitflow.prefix.feature)
    if ! startswith "$NAME" "$PREFIX"; then
        NAME=$PREFIX""$NAME
    fi
elif [ "$SUBCMD" == "release" ]; then
    # Prepend the feature prefix to the branch name if not provided
    PREFIX=$(git config --get gitflow.prefix.release)
    if ! startswith "$NAME" "$PREFIX"; then
        NAME=$PREFIX""$NAME
    fi
elif [ "$SUBCMD" == "hotfix" ]; then
    # Prepend the feature prefix to the branch name if not provided
    PREFIX=$(git config --get gitflow.prefix.hotfix)
    if ! startswith "$NAME" "$PREFIX"; then
        NAME=$PREFIX""$NAME
    fi
fi

# Ensure that this script has been initialized
if [ "$SUBCMD" != "init" ]; then
    git_require_this_script_init
fi

# Ensure a git repo
git_require_git_repo_dir


# Git flow functionality - override some of the actions to increase the usability
if [ "$SUBCMD" == "init" ]; then
    git flow init -df
    git config gitflow.feature.start.fetch true
    SCRIPT_PATH=${0}
    echo ""
    echo alias gf="'"$SCRIPT_PATH"'" >> ~/.bash_profile
    source ~/.bash_profile
elif [ "$SUBCMD" == "feature" -a "$ACTION" == "list" ]; then
    # Enforce verbose when listing features, just because it is nice.
    git flow "$@" -v
elif [ "$SUBCMD" == "feature" -a "$ACTION" == "rebase" ]; then
    echo "This command contains overriden functionality compared to standard git flow."
    echo "Perform a merge if we any of the following conditions are met:"
    echo "- The feature branch track a remote server"
    echo "- There has been an earlier merge commit"
    echo "- There is a conflict when trying to rebase.(?)"
    echo ""

    # Ensure that we have a clean working directory
    git_require_clean_working_tree
	
    # Should we pull in the latest changes on the develop branch?
    FETCH_BEFORE=$(git config gitflow.feature.start.fetch | grep 'true' -q)
    if $FETCH_BEFORE ; then
        git_pull_develop
    fi
	
    # Ensure that the given branch is the checked out one
    if [ "$CURRENT_BRANCH" != "$NAME" ]; then
        git checkout $NAME
    fi
	
    # Specify what type of merge we should do, a rebase or a merge. Default is rebase.
    TYPE="rebase"
	
    # Enforce merge if the branch has been published
    if git rev-parse --symbolic-full-name @{u} 2>&1 | grep -v 'no upstream configured for branch' -q ; then
        TYPE="merge"
    fi
	
    # Enforce merge if there is a risk for a conflict
    CONFLICTS=$(git merge-tree `git merge-base $NAME $DEVELOP_BRANCH` $DEVELOP_BRANCH $NAME | grep '>>>>>>' -q && echo 1 || echo 0)
    if [ "$CONFLICTS" == "1" ]; then
        TYPE="merge"
    fi
	
    # Enforce merge if there has been previous merge commits within this feature branch
    MERGE_COMMITS=$(git log --left-right --graph --cherry-pick --oneline $DEVELOP_BRANCH..$NAME --merges | wc -l)
    if [ $MERGE_COMMITS -gt 0 ]; then
        TYPE="merge"
    fi

    if [ "$TYPE" == "merge" ]; then
        echo ""
        if [ "$CONFLICTS" == "1" ]; then
            echo "There will be a conflict when merging in the latest commmits from develop"
            echo "If you prefer to perform the merge within your IDE instead, you should abort"
            read -p "To continue press Enter, to abort press CTRL+C: "
        fi
		
        echo "git merge $DEVELOP_BRANCH"
        echo ""
        git merge $DEVELOP_BRANCH
    else
        echo git flow "$@"
    fi
elif [ "$SUBCMD" == "release" -a "$ACTION" == "version" ]; then
    VERSION=$(git_get_version_from_branch_name)
    echo "Release $VERSION"
	
    # TODO: Add validation of the format of the version - should follow the semantic version name standard x.x.x
	
    # Ensure that we have a clean working directory
    git_require_clean_working_tree
	
    # Do the release
    git flow release start $VERSION
    echo $VERSION > $VERSION_FILE
    git add $VERSION_FILE
    git commit -m "Bumped version number to $VERSION"
    git flow release finish -p -m "Release " $VERSION
elif [ "$SUBCMD" == "hotfix" -a "$ACTION" == "start" ]; then
    VERSION=$(git_get_version_from_branch_name)
    echo "Hotfix $VERSION"
    git flow hotfix start $VERSION
    echo $VERSION > $VERSION_FILE
    git add $VERSION_FILE
    git commit -m "Bumped version number to $VERSION (hotfix)"
    echo ""
    echo "- The version number has now been bumped to $VERSION"
elif [ "$SUBCMD" == "hotfix" -a "$ACTION" == "finish" ]; then
    VERSION=$(git_get_version_from_branch_name)
    echo "Hotfix $VERSION"
    git flow hotfix finish -p -m "Hotfix " $VERSION
else
    # By default we fall back on just passing through all arguments to git flow.
    git flow "$@"
fi

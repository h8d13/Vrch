#!/usr/bin/env bash
set -euo pipefail

# publish out/ as the single commit of the dist branch, run after repo.sh
# force push replaces the old commit, so old binaries leave history
# temp index: master's index and worktree stay untouched
cd "$(dirname "$0")"
root=$PWD
# shellcheck source=repack.sh
source "$root/repack.sh"

repo=${REPO:-vrch}
dest=$root/out/$repo/$(uname -m)
if [[ ! -e $dest/$repo.db ]]; then
	echo "$dest: no repo db, run repo.sh first" >&2
	exit 1
fi

# git rejects an empty index file, let it create one in a temp dir
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_INDEX_FILE=$tmp/index

# repo-add leaves .old db backups, local only
git -C "$root/out" --git-dir="$root/.git" --work-tree=. \
	add -A -- . ':!*.old' ':!*.old.sig'
tree=$(git write-tree)

# lease on the fetched head: a publish from the other machine in between
# is refused instead of overwritten. empty lease = must not exist yet
rc=0
fetch_dist || rc=$?
case $rc in
0)
	lease=$(git rev-parse FETCH_HEAD)
	if [[ $tree == "$(git rev-parse 'FETCH_HEAD^{tree}')" ]]; then
		echo "$dist_branch: already up to date"
		exit 0
	fi
	;;
2)
	lease=
	;;
*)
	exit 1
	;;
esac

commit=$(git commit-tree "$tree" -m "publish: $repo $(uname -m)")
git push --force-with-lease="$dist_branch:$lease" origin \
	"$commit:refs/heads/$dist_branch"

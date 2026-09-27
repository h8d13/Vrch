#!/usr/bin/env bash
set -euo pipefail

# read-only half of repo.sh: which packages need a build
# no clone, build, signing or metadata writes, so it runs in CI as is
# only writes out/ (ignored) when seeding it from the published branch
# exit 0 all up to date, 2 some need building (repo.sh), 1 error
cd "$(dirname "$0")"
root=$PWD
# shellcheck source=repack.sh
source "$root/repack.sh"

# devtools maps package names to packaging repo urls
pacman -T devtools git || { echo "missing host deps" >&2; exit 1; }

repo=${REPO:-vrch}
dest=$root/out/$repo/$(uname -m)
seed_out "$root/out" "$dest/$repo.db" || exit 1

stale=0
for dir in "$root"/pkgs/*/; do
	pkg=$(basename "$dir")
	validate_patches "$dir" || exit 1
	sum=$(patches_sum "$dir")
	reasons=$(build_reasons "$pkg" "$dir$meta_name" "$sum" "$dest") ||
		exit 1
	if [[ -z $reasons ]]; then
		echo "$pkg: up to date"
	else
		echo "$pkg: needs build ($reasons)"
		stale=1
	fi
done

((stale)) && exit 2
exit 0

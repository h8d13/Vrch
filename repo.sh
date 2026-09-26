#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
root=$PWD

# prints missing names, non-zero exit
pacman -T devtools base-devel git gnupg || { echo "missing host deps" >&2; exit 1; }

# chroot builds for host arch.
# PKGDEST must exist, else makechrootpkg falls back to PKGBUILD dir
repo=${REPO:-vrch}
dest=$root/out/$repo/$(uname -m)
mkdir -p "$dest"

# package files the patched PKGBUILD produces, as paths in dest
pkg_files() {
	(cd "$1" && PKGDEST="$dest" makepkg --packagelist)
}

# when every package file of the patched version is already in dest
# listed -debug is skipped by makepkg when there are no symbols
is_built() {
	local f
	for f in $(pkg_files "$1"); do
		[[ -f $f || $f == *-debug-* ]] || return 1
	done
}

rm -rf build && mkdir build && cd build
todo=() new=()
for dir in "$root"/pkgs/*/; do
	pkg=$(basename "$dir")
	pkgctl repo clone --protocol https "$pkg"
	# we purposely exclude any path to metadata here, might have moved
	# makes for PKGBUILD as single source of truth.
	git -C "$pkg" apply -3 --exclude=.SRCINFO "$dir"*.patch || {
		echo "$pkg: patches conflict with upstream" >&2
		exit 1
	}
	# own rel suffix: distinct cache filename, sorts above upstream
	# makepkg allows one dot, so N -> N.90 and N.M -> N.M90
	rel=$(sed -n 's/^pkgrel=//p' "$pkg/PKGBUILD")
	[[ $rel == *.* ]] && rel+="90" || rel+=".90"
	sed -i "s/^pkgrel=.*/pkgrel=$rel/" "$pkg/PKGBUILD"
	# regen from patched PKGBUILD, survives upstream moves
	(cd "$pkg" && makepkg --printsrcinfo > .SRCINFO)
	# same version = same filename, rebuild would break users' caches
	if is_built "$pkg"; then
		echo "$pkg: up to date, skipping"
	else
		todo+=("$pkg")
		mapfile -t files < <(pkg_files "$pkg")
		new+=("${files[@]}")
		# upstream source signing keys ship with the packaging repo
		if [[ -d $pkg/keys/pgp ]]; then
			gpg --import "$pkg"/keys/pgp/*.asc
		fi
	fi
done

((${#todo[@]})) || { echo "nothing to build"; exit 0; }

# repo (core/extra/multilib) auto-detected per pkgbase
PKGDEST="$dest" pkgctl build -c "${todo[@]}"

# only this run's packages, repo-add warns on every re-added entry
cd "$dest"
added=()
for f in "${new[@]}"; do
	[[ -f $f ]] || continue
	gpg --yes --detach-sign "$f"
	added+=("$f")
done
# -s sign db, -v verify existing db sig, -R drop files of replaced versions
repo-add -s -v -R "$repo.db.tar.zst" "${added[@]}"

# repo-add always symlinks when fs allows, static hosts serve link text
for db in "$repo.db" "$repo.files"; do
	cp --remove-destination "$db.tar.zst" "$db"
	cp --remove-destination "$db.tar.zst.sig" "$db.sig"
done

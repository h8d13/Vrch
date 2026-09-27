#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
root=$PWD
# shellcheck source=repack.sh
source "$root/repack.sh"

# prints missing names, non-zero exit
pacman -T devtools base-devel git gnupg || { echo "missing host deps" >&2; exit 1; }

# identity comes from makepkg.conf, both machines sign with their own key
packager=$(makepkg_conf PACKAGER)
gpgkey=$(makepkg_conf GPGKEY)
is_packager_valid "$packager" || {
	echo "PACKAGER '$packager' invalid, set it in makepkg.conf" >&2
	exit 1
}
validate_signing_key "$gpgkey" "$root/vrch.pub" || exit 1

# chroot builds for host arch.
# PKGDEST must exist, else makechrootpkg falls back to PKGBUILD dir
repo=${REPO:-vrch}
dest=$root/out/$repo/$(uname -m)
seed_out "$root/out" "$dest/$repo.db" || exit 1
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
declare -A revs sums
for dir in "$root"/pkgs/*/; do
	pkg=$(basename "$dir")
	meta=$dir$meta_name
	validate_patches "$dir" || exit 1
	sum=$(patches_sum "$dir")
	rev=$(next_rev "$meta" "$sum")
	revs[$pkg]=$rev sums[$pkg]=$sum
	# record only written once artifacts match, same inputs = nothing to do
	reasons=$(build_reasons "$pkg" "$meta" "$sum" "$dest") || exit 1
	if [[ -z $reasons ]]; then
		echo "$pkg: upstream and patches unchanged, skipping"
		touch_meta "$meta"
		continue
	fi
	pkgctl repo clone --protocol https "$pkg"
	if [[ $reasons == *moved* ]]; then
		echo "$pkg: upstream moved since last build"
		upstream_log "$pkg" "$meta"
	fi
	if [[ $reasons == *patched* ]]; then
		echo "$pkg: patches changed, rev $rev"
	fi
	if [[ $reasons == missing ]]; then
		echo "$pkg: artifacts missing from $dest, rebuilding"
	fi
	git -C "$pkg" apply -3 "$dir"*.patch || {
		echo "$pkg: patches conflict with upstream" >&2
		exit 1
	}
	# own rel suffix: distinct cache filename, sorts above upstream
	# makepkg allows one dot, so N -> N.90 and N.M -> N.M90 (rev 0)
	rel=$(sed -n 's/^pkgrel=//p' "$pkg/PKGBUILD")
	suffix=$((rel_base + rev))
	[[ $rel == *.* ]] && rel+="$suffix" || rel+=".$suffix"
	sed -i "s/^pkgrel=.*/pkgrel=$rel/" "$pkg/PKGBUILD"
	# regen from patched PKGBUILD, survives upstream moves
	(cd "$pkg" && makepkg --printsrcinfo > .SRCINFO)
	# same version = same filename, rebuild would break users' caches
	if is_built "$pkg"; then
		echo "$pkg: up to date, skipping"
		# first run over existing artifacts has no record yet
		if ! touch_meta "$meta"; then
			mapfile -t files < <(pkg_files "$pkg")
			write_meta "$pkg" "$meta" "$rev" "$sum" "${files[@]}"
		fi
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

# build succeeded, artifacts now come from these upstream heads + patches
for pkg in "${todo[@]}"; do
	mapfile -t files < <(pkg_files "$pkg")
	write_meta "$pkg" "$root/pkgs/$pkg/$meta_name" \
		"${revs[$pkg]}" "${sums[$pkg]}" "${files[@]}"
done

# only this run's packages, repo-add warns on every re-added entry
cd "$dest"
added=()
for f in "${new[@]}"; do
	[[ -f $f ]] || continue
	gpg -u "$gpgkey" --yes --detach-sign "$f"
	added+=("$f")
done
# -s sign db, -k with this machine's key, -v verify existing db sig
# -R drop files of replaced versions
repo-add -s -k "$gpgkey" -v -R "$repo.db.tar.zst" "${added[@]}"

# repo-add always symlinks when fs allows, static hosts serve link text
for db in "$repo.db" "$repo.files"; do
	cp --remove-destination "$db.tar.zst" "$db"
	cp --remove-destination "$db.tar.zst.sig" "$db.sig"
done

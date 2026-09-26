#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
root=$PWD

# prints missing names, non-zero exit
pacman -T devtools base-devel git gnupg || { echo "missing host deps" >&2; exit 1; }

rm -rf build && mkdir build && cd build
for dir in "$root"/pkgs/*/; do
	pkg=$(basename "$dir")
	pkgctl repo clone --protocol https "$pkg"
	# we purposely exclude any path to metadata here, might have moved
	# makes for PKGBUILD as single source of truth.
	git -C "$pkg" apply -3 --exclude=.SRCINFO "$dir"*.patch || {
		echo "$pkg: patches conflict with upstream" >&2
		exit 1
	}
	# regen from patched PKGBUILD, survives upstream moves
	(cd "$pkg" && makepkg --printsrcinfo > .SRCINFO)
done

# repo (core/extra/multilib) auto-detected per pkgbase
# PKGDEST must exist, else makechrootpkg falls back to PKGBUILD dir
mkdir -p "$root/out"
PKGDEST="$root/out" pkgctl build -c */

# rebuilt same version overwrites pkg, so stale sig means older than pkg
cd "$root/out"
for p in *.pkg.tar.zst; do
	[[ $p.sig -nt $p ]] || gpg --yes --detach-sign "$p"
done
# -s sign db, -v verify pkg sigs, -R drop files of replaced versions
repo-add -s -v -R vrch.db.tar.zst *.pkg.tar.zst

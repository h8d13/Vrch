# Vrch

> `vrch` is a repack utility that uses `*.patch` files to modify PKGBUILDs
> and builds them in clean chroots, mostly aims to test pkg-splitting.

This makes testing patches faster and have reference implementations
(`*-docs`, `*-gtk`, `*-qt`, `*-...`).

> It generates `.SRCINFO` files automatically and uses a custom format:
> `.RPKGINFO` to track upstream commits and patches revisions...

This aims at [`namcap`](https://gitlab.archlinux.org/pacman/namcap/-/work_items/108) `lots-of-docs` rules amongst other things.

---

## Signatures:

```
curl -O https://raw.githubusercontent.com/h8d13/Vrch/master/vrch.pub
sudo pacman-key --add vrch.pub
sudo pacman-key --lsign-key 83CE533ED3212DA833DA03034066352FC2E0674B
sudo pacman-key --lsign-key D614130877C531F18CCBEFBC5D54CFFDD550A51F
```

Pubkey IDs: [`83CE533ED3212DA833DA03034066352FC2E0674B`](./vrch.pub),
[`D614130877C531F18CCBEFBC5D54CFFDD550A51F`](./vrch.pub)

## Repos:

Then edit `/etc/pacman.conf`
> Add above `[core]` if desired. Or `pacman -S vrch/somepkg`

```
[vrch]
SigLevel = Required
Server = https://raw.githubusercontent.com/h8d13/Vrch/dist/$repo/$arch
```

---

## Licenses:

Everything in this repository is licensed under [0BSD](./LICENSE).

Built packages keep their [upstream](https://gitlab.archlinux.org/archlinux/packaging/packages) licenses.

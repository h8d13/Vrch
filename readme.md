# Vrch

> `vrch` is a repack utility that uses `*.patch` files to modify PKGBUILDs
> and builds them in clean chroots, mostly aims to make pkg splits easier.

Signatures:

```
curl -O https://raw.githubusercontent.com/h8d13/Vrch/master/vrch.pub
sudo pacman-key --add vrch.pub
sudo pacman-key --lsign-key 83CE533ED3212DA833DA03034066352FC2E0674B
```

Pubkey ID: [`83CE533ED3212DA833DA03034066352FC2E0674B`](./vrch.pub)

Repos:

Then edit `/etc/pacman.conf`
> Add above `[core]` if desired. Or `pacman -S vrch/somepkg`

```
[vrch]
SigLevel = Required
Server = https://raw.githubusercontent.com/h8d13/Vrch/master/out/$repo/$arch
```

---

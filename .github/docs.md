## Examples / Philosophy

Examples splits:

- [`libguestfs`](https://gitlab.archlinux.org/archlinux/packaging/packages/libguestfs/-/commit/e67304a4ad46f9c769f919acc4394228fcffd559)
- [`suil`](https://gitlab.archlinux.org/archlinux/packaging/packages/suil/-/blob/main/PKGBUILD?ref_type=heads)

---

This also adheres closer to: https://wiki.archlinux.org/title/Arch_Linux#Simplicity

> Arch Linux official packages do not provide system-wide GUI configuration utilities (i.e. there is neither a GUI installation wizard nor a GUI system configuration tool,
> and Arch as a distribution does not promote GUI tools for system configuration), encouraging users to perform most system configuration from a command-line shell and a text editor.

Packages including "debug UI tools" or non-essential, examples include splitting `-gtk`, `-qt` or `-somesidecomponent`.

- [`avahi`](https://gitlab.archlinux.org/archlinux/packaging/packages/avahi/-/merge_requests/4.diff)
- [`v4l-utils`](https://gitlab.archlinux.org/archlinux/packaging/packages/v4l-utils/-/merge_requests/1.diff)

> In a similar fashion, Arch ships the configuration files provided by upstream with changes limited to distribution-specific issues like adjusting the system file paths.
> It does not add automation features such as enabling a service simply because the package was installed.
> Packages are only split when compelling advantages exist, such as to save disk space in particularly bad cases of waste.

Believe the **same should be true to**: [docs](https://github.com/h8d13/dontreadthedocs) with the Alpine [precedent](https://wiki.alpinelinux.org/wiki/Creating_an_Alpine_package#subpackages) (which I find very neat).
Where a `-docs` convention already exists. I,e: [`wireplumber-docs`](https://gitlab.archlinux.org/archlinux/packaging/packages/wireplumber/-/blob/main/PKGBUILD?ref_type=heads)

These obviously take a **bit of work and due process**, but make for a smaller and more "explicit" system.

---

## Approaches

This is essentially to get rid of the following boilerplate:
```diff
+_pick() {
+  local p="$1" f d; shift
+  for f; do
+    d="$srcdir/$p/$f"
+    mkdir -p "$(dirname "$d")"
+    mv "$f" "$d"
+    rmdir -p --ignore-fail-on-non-empty "$(dirname "$f")"
+  done
```

`makepkg` has no built-in split partitioner.
There is a maintainer's richer declarative [alternative](https://gitlab.archlinux.org/pacman/pacman/-/tree/allan/splitpkg2)

Full thread: https://gitlab.archlinux.org/pacman/pacman/-/merge_requests/314#note_561561

Arch's very own tooling describes [namcap](https://gitlab.archlinux.org/pacman/namcap/-/work_items/108) `lots-of-docs` rule as more than 50%.

This ties back directly to the "bad cases of waste" seen above.

---

## More...

Should help with: https://alpm.archlinux.page/specifications/alpm-sonamev2.7.html
"autodeps", the more splits, the less tangled things are... or at least that's how I understood it.

But back to our wasted space concept...

The theory is the following, lets say you save ~30MB on 3 packages (at installed/extracted size).
Over the network this size is compressed, let's take 6:1 as a reference: 5MB saved over the wire.
Multiply this by the amount of users, AND each release of said packages.

> Pacman removed delta updates years ago, so every new release of a package is downloaded in full by every machine that has it.
> Inversly it costs more on database syncs (more packages to sync).

(Add to this CI, container images, etc).

As a rough, illustrative example: 5 MB (3 packages) × 100,000 affected machines × 10 releases a year:
==> Comes to about 5TB a year.

```
bsdtar --no-fflags --no-read-sparse -cnf - --null --files-from  COMPRESSZST=(zstd -c -T0 --ultra -20 -)
```

> While compression works amazing on certain things (like html docs ~15:1) it still ends up in full, on the users' systems.
BUT this is not the case to all types: like a PNG icon which will barely get any compression at all or binaries/plain-text where the compression is mid.

On another note: split packages (and regular ones) often also duplicate licenses everywhere, meaning an full desktop install might have several MBs of license files.
Which are for the most part exactly identical but for the <name/company> <year> + SPDX headers/folder in each file.

Or even better be like VSC Chromium and ship 15MB HTML licenses, 27k lines long (xdxd).

For split packages this is relevant again where we can assume the license is the same (usually, and the parent package is likely already installed)
What I mean is also to be able to get rid of having to do:

```bash
  install -Dm644 openjpeg-"${pkgver}"/LICENSE \
    -t "${pkgdir}"/usr/share/licenses/${pkgname}/
```
For each split... repeat X times.

---

Whilst these were first examples of "end-user" applications. Developper tools are just as, if not more concerned:

For instance `llvm` generates a whooping ~50MB of docs.

Which is great, if you are going to read them... But likely you just installed `clangd` which itself pulls in ~21MB.
Anyways you probably understand the pattern at this point.

## Conclusion

So if we combine our reasoning here:

1. More explicit systems: "Decide what you want to install", follows the philosophy points above, closer IMO.
2. Respects more end-users: (who do not have a lot of space or internet access/speed) and the server(s) used.
3. Makes for slightly more packaging work. But which is questionable in upstream in the first place: ie, bundling debug/docs/tools in an "end-product" based on deps detection.

The effort to me here is worth the reward. Which has always been smaller, faster, more declarative systems.

---

This whole experiment started with a report you can find here [`coreutils symlink locales bug`](https://gitlab.archlinux.org/archlinux/packaging/packages/coreutils/-/work_items/10)

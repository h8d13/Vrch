<!--
---
draft: true
title: "0000 Package splits: formal rules and tooling"
---
-->

# Package splits: formal rules and tooling

<!--
- Date proposed: 2026-10-31
- RFC MR: <https://gitlab.archlinux.org/archlinux/rfcs/-/merge_requests/0000>
  **update this number after RFC merge request has been filed**
-->

## Summary

Community effort on package splits, i.e. `*-docs`, `*-gtk`, `*-qt`, `*-somesidecomponent`, and corresponding "meta" packages.

Goals:

1. More explicit systems: "decide what you want to install", closer to the Arch philosophy.
2. Less space/bandwidth used on end-users' disks and less load on mirrors.
3. Less packaging work per split, through `makepkg` and `namcap` support instead of per-PKGBUILD boilerplate.

## Motivation

I believe this is a well-known "thing" amongst packagers, and a current "hot topic" when it comes to internal tools.

To illustrate, I've gathered links/sections from the wiki/GitLab that are relevant.

To start with a more "abstract" motivation: https://wiki.archlinux.org/title/Arch_Linux#Simplicity

> Arch Linux official packages do not provide system-wide GUI configuration utilities (i.e. there is neither a GUI installation wizard nor a GUI system configuration tool,
> and Arch as a distribution does not promote GUI tools for system configuration), encouraging users to perform most system configuration from a command-line shell and a text editor.

The same applies to packages including "debug UI tools" or other non-essentials. Examples:

- [`avahi`](https://gitlab.archlinux.org/archlinux/packaging/packages/avahi/-/merge_requests/4)
- [`v4l-utils`](https://gitlab.archlinux.org/archlinux/packaging/packages/v4l-utils/-/merge_requests/1)

> In a similar fashion, Arch ships the configuration files provided by upstream with changes limited to distribution-specific issues like adjusting the system file paths.
> It does not add automation features such as enabling a service simply because the package was installed.

> Packages are only split when compelling advantages exist, such as to save disk space in particularly bad cases of waste.

This RFC does not argue against that last rule: it argues that docs and side components regularly **meet** it.
The `openjpeg2` example below cuts 94.7 % of installed size, which is a "particularly bad case of waste" by any measure.
Yet was also [closed](https://gitlab.archlinux.org/archlinux/packaging/packages/openjpeg2/-/merge_requests/1) directly.

Splits already happen in `extra`:

- [`libguestfs`](https://gitlab.archlinux.org/archlinux/packaging/packages/libguestfs/-/commit/e67304a4ad46f9c769f919acc4394228fcffd559)
- [`suil`](https://gitlab.archlinux.org/archlinux/packaging/packages/suil/-/blob/main/PKGBUILD?ref_type=heads)
- A `-docs` convention also exists, i.e. [`wireplumber-docs`](https://gitlab.archlinux.org/archlinux/packaging/packages/wireplumber/-/blob/main/PKGBUILD?ref_type=heads)

These take a **bit of work and due process**, but make for a smaller and more "explicit" system.
The problems below are what make that work harder than it needs to be.

### Problem 1: `PKGBUILD` boilerplate

`makepkg` has no built-in split partitioner, so each split PKGBUILD carries something like:

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

There is a maintainer's richer declarative [alternative](https://gitlab.archlinux.org/pacman/pacman/-/tree/allan/splitpkg2).

Full [thread](https://gitlab.archlinux.org/pacman/pacman/-/merge_requests/314#note_561561)
has been lingering for 6+ months, on how to handle splits with built-in functions, instead of the boilerplate above.

### Problem 2: Lint rules

Arch's own tooling, [`namcap`](https://gitlab.archlinux.org/pacman/namcap/), defines the `lots-of-docs` rule as docs making up more than 50 % of a package.

This ties back directly to the "bad cases of waste" seen above.

As seen in my bug report [108](https://gitlab.archlinux.org/pacman/namcap/-/work_items/108), the checked paths were wrong, and **do not cover all common docs paths**.

A simple [`pyalpm` script](https://github.com/h8d13/Vrch/blob/master/scripts/drtfm.py) let's you query your packages-db with more paths and top candidates.

### Problem 3: Duplicated licenses

Split packages restate licenses for each split:

```shell
  install -Dm644 openjpeg-"${pkgver}"/LICENSE \
    -t "${pkgdir}"/usr/share/licenses/${pkgname}/
```

Repeated for every split, where the license is (usually) the same and the parent package is likely already installed.
More broadly, a full desktop install carries several MiB of license files that are identical except for the `<name/company> <year>` and SPDX headers.

### More precedents

Alpine Linux [precedent](https://wiki.alpinelinux.org/wiki/Creating_an_Alpine_package#subpackages):
it always splits, and documents it as such for future packagers.

Quoting @Toolybird:
> But having said all that, there has been a push to "fix" situations like this in preparation for upcoming `alpm-sonamev2`/"autodeps".

See the [`alpm-sonamev2`](https://alpm.archlinux.page/specifications/alpm-sonamev2.7.html) specification.
The more granular the packages, the less tangled the dependency graph.

## Specification

### Proposals

1. **`makepkg`: built-in split partitioning.**

Land a declarative mechanism (i.e. [`splitpkg2`](https://gitlab.archlinux.org/pacman/pacman/-/tree/allan/splitpkg2) / [MR 314](https://gitlab.archlinux.org/pacman/pacman/-/merge_requests/314)) so splits no longer need the `_pick()` boilerplate.

2. **`namcap`: stricter `lots-of-docs`.**

 Fix the checked paths to cover common docs locations, and lower the warning threshold from 50 % to 25-30 %. It is only a warning, so a lower threshold costs little.

3. **Naming conventions.**

Define standard suffixes so splits look familiar to users: `*-docs`, `*-gtk`, `*-qt`, and what else is common? `*-completions`, `*-dev`, `*-lang`, `*-dbg` (see Unresolved Questions).

4. **License deduplication.**

Let `makepkg` handle licenses for split packages sharing the parent's license (i.e. symlink instead of a hard copy, if parent present), removing the per-split `install` line.

### Micro-analysis

Example `openjpeg2 2.5.4`:
|                          | Download   | Installed  |
|--------------------------|------------|------------|
| Official (`extra`)       | 895.61 KiB | 13.37 MiB  |
| Without `-docs`          | 273.11 KiB | 722.71 KiB |
| Delta                    | -69.5 %    | -94.7 %    |
| With `-docs` (optional)  | 605.18 KiB | 12.89 MiB  |

Built in a clean chroot from the official PKGBUILD with this [patch](https://github.com/h8d13/Vrch/blob/master/pkgs/openjpeg2/split-docs.patch) applied.

`openjpeg2` is pulled in by almost everything a desktop user would use (document editor, file manager, etc.).

> The difference IS usually `doxygen`, `graphviz` versions recorded in `.BUILDINFO`

And is already be checked using [`checkpkg`](https://gitlab.archlinux.org/archlinux/devtools/-/blob/master/src/checkpkg.in) from `devtools` with the incoming/outgoing `<||>` lists.

A more "dev-ish" example, `clangd`: pulls in ~21 MiB of docs, then `llvm` pulls in another ~50 MiB.

Compression helps over the wire (HTML docs compress ~15:1), but the full size still ends up on users' systems.
It also varies by type: PNG icons barely compress, binaries and plain text sit somewhere in between.

Man pages are deliberatly almost always left in the base package or split only if they have several.

### Macro-analysis

Since pacman 5.2 removed delta upgrades:
```
API CHANGES BETWEEN 5.1 AND 5.2
===============================

[REMOVED]
- package delta support
```

This means **each release** of a package is downloaded in full by every machine that has it, docs and debug UI tools included.

As a rough, illustrative example: saving ~30 MiB installed across 3 packages, at a ~6:1 compression ratio, is ~5 MiB over the wire.
5 MiB × 100,000 affected machines × 10 releases a year comes to about 5 TB a year, for 3 packages. (Add to this CI, container images, etc.)

As seen in monitoring (https://dashboards.archlinux.org/dashboards), the load on mirrors makes this a compelling argument.

The same applies to end-users:

- Differences in speed/cost/accessibility of "good" internet: https://www.speedtest.net/global-index
- Storage prices/speed: https://pcpartpicker.com/trends/price/internal-hard-drive/

## Drawbacks

The main drawback is errors in packaging when performing these splits, plus added complexity and bus factor (see below).

Second, overdoing splits might confuse users wondering why they don't have X or Y. "Meta" packages solve this.

Finally, more packages means more entries in the sync databases, so each sync costs slightly more.

Measured on `extra.db` (repacked with/without its 213 `*-docs` entries): ~764 B per split entry (gzip), paid by every machine on every db download.
Docs would need to be truly tiny (i.e. a few KiB), this might tip the scale in favor of not splitting, but this is unrealistic compared to real world cases.

## Unresolved Questions

### Unresolved 1: Bus factor / Infrastructure

Certain packagers handle much more complex packages overall (i.e. the extreme `qemu` or `vlc` splits).
The bus factor (how many people actively work on packaging, tools, ...) isn't mine to answer, but it's one I'd help with where I can.

### Unresolved 2: Package Maintainer style / "It's small"

A packager might say "I'd like to keep my PKGBUILDs simple", or "this package is already small".
The former is solved by the changes in `makepkg`; the latter is relative to how much of the package is split out.

Total size isn't indicative of how much a split is beneficial: this should be judged in percentages/ratios, not by whether the package is "small" (when compressed) to begin with.
Compound this per package, per release (without delta upgrades), per affected machine, as in the Micro-analysis above.

### Unresolved 3: Defining conventions

Which suffix categories to standardize, i.e. `*-completions`, `*-dev`, `*-lang`, `*-dbg`.
With pre-defined categories, a packager can be as specific as they wish, while the result stays familiar to users.

## Alternatives Considered

I have a GitHub repo that documents and tests most of the patches: https://github.com/h8d13/Vrch/
It builds patched official PKGBUILDs in clean chroots, and serves as a reference implementation for the numbers above.
There is also a Reddit [discussion](https://www.reddit.com/r/archlinux/comments/1wpur5n/on_a_mission_making_everyones_systems_lighter/)
Where some back-and-forth happened before drafting this RFC, where the biggest argument was simply that developpers' time is in short supply.

This whole rabbit-hole started with a [`coreutils` symlink locales bug](https://gitlab.archlinux.org/archlinux/packaging/packages/coreutils/-/work_items/10).

The alternative is to keep bundling whatever a `meson` or `cmake` (or other) build installs. Some consider that the "KISS" option, but I disagree.
Explicit wins over implicit: the build stays the same, only the packaging changes. A maintainer pays the cost once, and all down-stream (users, infra) benefits.

And any decision handed back to the power-user is a "win" in terms of Arch philosophy.

#!/usr/bin/env python3

# Requires pyalpm (pacman -S pyalpm)
# Rank installed Arch packages by how much of their size is documentation.

import argparse
import os
import re
import stat

import pyalpm

# Superset of Namcap/rules/lotsofdocs.py: adds info and GNOME help.
# Man pages are left out: Arch keeps them in the base package even when
# a -docs split exists.
# Modified logic from:
# https://gitlab.archlinux.org/h8d13/namcap/-/tree/dot-docsratio

DOCDIRS = (
    "usr/share/doc/",
    "usr/share/gtk-doc/",
    "usr/share/devhelp/books/",
    "usr/share/info/",
    "usr/share/help/",
)
DOCDIRS_RE = re.compile(r"usr/lib/ruby/gems/[^/]+/doc/")


def is_doc(name):
    return name.startswith(DOCDIRS) or bool(DOCDIRS_RE.match(name))


def root_causes(db, pkg):
    # Walk reverse deps like `pactree -r`, stopping at explicitly installed
    # packages: those are why pkg is on the system at all.
    seen = {pkg.name}
    queue = [pkg]
    roots = set()
    while queue:
        for name in queue.pop().compute_requiredby():
            if name in seen:
                continue
            seen.add(name)
            dep = db.get_pkg(name)
            if dep.reason == pyalpm.PKG_REASON_EXPLICIT:
                roots.add(name)
            else:
                queue.append(dep)
    return sorted(roots)


def why(db, name, limit=3):
    pkg = db.get_pkg(name)
    if pkg.reason == pyalpm.PKG_REASON_EXPLICIT:
        return "explicit"
    roots = root_causes(db, pkg)
    if not roots:
        # Dep of nothing explicit: orphan, or kept only as an optdep
        opt = pkg.compute_optionalfor()
        return f"optional for {', '.join(opt)}" if opt else "orphan"
    more = f" +{len(roots) - limit}" if len(roots) > limit else ""
    return ", ".join(roots[:limit]) + more


def scan(db, root):
    rows = []
    for pkg in db.pkgcache:
        # namcap skips these too
        if pkg.name.endswith(("-doc", "-docs")):
            continue
        total = docs = 0
        for name, _size, _mode in pkg.files:
            # The local DB has no file sizes, so stat the installed file.
            # Symlinks and directories count as 0, as they do in a package tarball.
            try:
                st = os.lstat(os.path.join(root, name))
            except OSError:
                continue
            size = st.st_size if stat.S_ISREG(st.st_mode) else 0
            total += size
            if is_doc(name):
                docs += size
        if total:
            rows.append((docs / total, docs, total, pkg.name))
    return rows


def print_table(db, title, rows, threshold):
    print(title)
    print(f"{'package':32} {'docs%':>6} {'docs':>9} {'total':>9}   why")
    for ratio, docs, total, name in rows:
        mark = "*" if ratio >= threshold else " "
        print(
            f"{name:32} {ratio * 100:5.1f}% {docs / 1e6:7.2f}MB {total / 1e6:7.2f}MB"
            f" {mark} {why(db, name)}"
        )
    print()


def main():
    parser = argparse.ArgumentParser(description="Rank installed Arch packages by how much of their size is documentation.")
    parser.add_argument(
        "-t",
        "--threshold",
        type=float,
        default=30,
        help="percent of docs to flag (default: 30)",
    )
    parser.add_argument(
        "-n", "--top", type=int, default=25, help="rows per table (default: 25)"
    )
    parser.add_argument("--root", default="/", help="installation root (default: /)")
    parser.add_argument(
        "--dbpath",
        default="/var/lib/pacman",
        help="pacman database path (default: /var/lib/pacman)",
    )
    args = parser.parse_args()
    threshold = args.threshold / 100

    # Keep the handle alive: the db and its packages borrow from it
    handle = pyalpm.Handle(args.root, args.dbpath)
    db = handle.get_localdb()
    rows = scan(db, args.root)
    flagged = sum(1 for r in rows if r[0] >= threshold)
    print(
        f"{len(rows)} installed packages checked, {flagged} at >= {args.threshold:g}% docs (marked *)\n"
    )
    print_table(
        db, "Worst by ratio:", sorted(rows, reverse=True)[: args.top], threshold
    )
    print_table(
        db,
        "Most docs by size:",
        sorted(rows, key=lambda r: r[1], reverse=True)[: args.top],
        threshold,
    )


if __name__ == "__main__":
    main()

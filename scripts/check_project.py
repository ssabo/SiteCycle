#!/usr/bin/env python3
"""Sanity-check SiteCycle.xcodeproj/project.pbxproj. Standard library only, runs on Linux.

The project file is edited by hand (no synchronized folders yet), so it's easy to
add a .swift file to disk but not to its target, reuse an object ID, or leave a
reference to a deleted file. This catches those before Xcode Cloud does.

Usage:
    python3 scripts/check_project.py              # check; exit 1 on any error
    python3 scripts/check_project.py --next-ids   # also print the next free object IDs

Checks:
  1. Every object ID is defined once, and every referenced ID is defined.
  2. Every file reference with a group-relative path exists on disk.
  3. Every .swift file under a target's folder (SiteCycle/, SiteCycleTests/, ...)
     is compiled by that target, and every compiled file exists.
  4. A file compiled into a target outside its own folder must be listed in
     SHARED_SOURCES below, with exactly those targets.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, "SiteCycle.xcodeproj", "project.pbxproj")

# Files deliberately compiled into more than one target. Update this when a file
# gains or loses a target membership (and CLAUDE.md's target table with it).
SHARED_SOURCES = {
    "SiteCycle/Connectivity/WatchAppState.swift": {
        "SiteCycle", "SiteCycleWatch", "SiteCycleWatchWidgets", "SiteCycleWidgets",
    },
}

ID_RE = re.compile(r"^[0-9A-F]{24}$")


# --- Minimal parser for the old-style (OpenStep) plist that project.pbxproj uses ---

TOKEN_RE = re.compile(
    r"""\s+|/\*.*?\*/|//[^\n]*|"((?:[^"\\]|\\.)*)"|([{}()=;,])|([^\s{}()=;,"]+)""",
    re.S,
)


def tokenize(text):
    pos = 0
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise ValueError(f"cannot tokenize at offset {pos}: {text[pos:pos + 40]!r}")
        pos = m.end()
        quoted, punct, bare = m.group(1), m.group(2), m.group(3)
        if quoted is not None:
            yield ("str", bytes(quoted, "utf-8").decode("unicode_escape"))
        elif punct is not None:
            yield (punct, punct)
        elif bare is not None:
            yield ("str", bare)


class Parser:
    def __init__(self, text):
        self.tokens = list(tokenize(text))
        self.i = 0
        self.duplicate_keys = []  # (dict path, key)

    def next(self):
        tok = self.tokens[self.i]
        self.i += 1
        return tok

    def expect(self, kind):
        tok = self.next()
        if tok[0] != kind:
            raise ValueError(f"expected {kind!r}, got {tok!r}")

    def value(self, path=""):
        kind, val = self.next()
        if kind == "{":
            result = {}
            while self.tokens[self.i][0] != "}":
                key = self.next()[1]
                self.expect("=")
                if key in result:
                    self.duplicate_keys.append((path, key))
                result[key] = self.value(f"{path}/{key}")
                self.expect(";")
            self.next()
            return result
        if kind == "(":
            result = []
            while self.tokens[self.i][0] != ")":
                result.append(self.value(path))
                if self.tokens[self.i][0] == ",":
                    self.next()
            self.next()
            return result
        if kind == "str":
            return val
        raise ValueError(f"unexpected token {val!r}")


def referenced_ids(value):
    if isinstance(value, dict):
        for k, v in value.items():
            if ID_RE.match(k):
                yield k
            yield from referenced_ids(v)
    elif isinstance(value, list):
        for v in value:
            yield from referenced_ids(v)
    elif isinstance(value, str) and ID_RE.match(value):
        yield value


# --- Checks ---

def resolve_paths(objects, main_group):
    """Map file-reference ID -> repo-relative path, for refs whose sourceTree is <group>."""
    paths = {}

    def walk(group_id, prefix):
        group = objects[group_id]
        if group.get("sourceTree", "<group>") != "<group>":
            return
        here = os.path.join(prefix, group["path"]) if "path" in group else prefix
        for child_id in group.get("children", []):
            child = objects.get(child_id, {})
            if child.get("isa") == "PBXFileReference":
                if child.get("sourceTree") == "<group>" and "path" in child:
                    paths[child_id] = os.path.normpath(os.path.join(here, child["path"]))
            elif child.get("isa") in ("PBXGroup", "PBXVariantGroup"):
                walk(child_id, here)

    walk(main_group, "")
    return paths


def target_sources(objects, paths):
    """Map target name -> set of compiled repo-relative paths (None for unresolvable refs)."""
    result = {}
    for obj in objects.values():
        if obj.get("isa") != "PBXNativeTarget":
            continue
        compiled = set()
        for phase_id in obj.get("buildPhases", []):
            phase = objects.get(phase_id, {})
            if phase.get("isa") != "PBXSourcesBuildPhase":
                continue
            for build_file_id in phase.get("files", []):
                file_ref = objects.get(build_file_id, {}).get("fileRef")
                compiled.add(paths.get(file_ref, f"<unresolved fileRef {file_ref}>"))
        result[obj["name"]] = compiled
    return result


def swift_files_on_disk(folder):
    found = set()
    for dirpath, _, filenames in os.walk(os.path.join(ROOT, folder)):
        for name in filenames:
            if name.endswith(".swift"):
                found.add(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return found


def next_free_ids(objects):
    used = {int(k, 16) for k in objects if ID_RE.match(k)}
    by_isa = {}
    for k, obj in objects.items():
        if ID_RE.match(k) and k.startswith("8A"):
            by_isa.setdefault(obj.get("isa"), []).append(int(k, 16))
    lines = []
    for isa in ("PBXFileReference", "PBXBuildFile", "PBXGroup"):
        ids = sorted(by_isa.get(isa, []))
        if not ids:
            continue
        # Next after the highest ID in the type's main block, skipping any ID in use.
        # (A few build files sit outside 0x100-0x1FF, so ignore outliers for the base.)
        median = ids[len(ids) // 2]
        block = [i for i in ids if (i >> 8) == (median >> 8)]
        candidate = max(block) + 1
        while candidate in used:
            candidate += 1
        lines.append(f"  next {isa}: {candidate:024X}")
    return lines


def main():
    with open(PBXPROJ, encoding="utf-8") as f:
        text = f.read()
    parser = Parser(text)
    project = parser.value()
    objects = project["objects"]
    errors = []

    for path, key in parser.duplicate_keys:
        errors.append(f"duplicate key {key} in {path or 'root'} (object ID reused?)")

    for ref in sorted(set(referenced_ids(project)) - set(objects)):
        errors.append(f"ID {ref} is referenced but never defined")

    synchronized = any(
        o.get("isa", "").startswith("PBXFileSystemSynchronized") for o in objects.values()
    )
    if synchronized:
        print("Synchronized folders in use: skipping file-membership checks (Xcode tracks them).")
    else:
        main_group = objects[project["rootObject"]]["mainGroup"]
        paths = resolve_paths(objects, main_group)
        for path in sorted(set(paths.values())):
            if not os.path.exists(os.path.join(ROOT, path)):
                errors.append(f"{path}: referenced in the project but missing on disk")

        sources = target_sources(objects, paths)
        compiled_by = {}
        for target, files in sources.items():
            for path in files:
                compiled_by.setdefault(path, set()).add(target)
                if path.startswith("<unresolved"):
                    errors.append(f"target {target}: compiles {path}")
                elif not os.path.exists(os.path.join(ROOT, path)):
                    errors.append(f"target {target}: compiles {path}, which is missing on disk")

        for target in sorted(sources):
            for path in sorted(swift_files_on_disk(target) - sources[target]):
                errors.append(
                    f"{path}: on disk but not compiled by target {target} "
                    f"(add a PBXFileReference, PBXGroup child, PBXBuildFile and Sources entry)"
                )

        for path, targets in sorted(compiled_by.items()):
            if path.startswith("<unresolved"):
                continue  # already reported above
            home = path.split(os.sep, 1)[0]
            outside = targets - {home}
            expected = SHARED_SOURCES.get(path)
            if expected is not None and targets != expected:
                errors.append(
                    f"{path}: compiled by {sorted(targets)}, expected {sorted(expected)} "
                    f"(see SHARED_SOURCES in this script)"
                )
            elif expected is None and outside:
                errors.append(
                    f"{path}: compiled by {sorted(outside)} outside its folder's target; "
                    f"if intended, add it to SHARED_SOURCES in this script and CLAUDE.md"
                )

    if "--next-ids" in sys.argv:
        print("Next free object IDs:")
        print("\n".join(next_free_ids(objects)))

    if errors:
        print(f"project.pbxproj: {len(errors)} problem(s)")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"project.pbxproj OK ({len(objects)} objects)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

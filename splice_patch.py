"""Splice a rewritten Edit patch back into a Markdown file, for rewrite-md.sh.

    python3 splice_patch.py FILE PATCH_FILE REWRITE_FILE OUT

Replaces the patch in FILE with the rewrite and writes the result to OUT, keeping
the patch's leading and trailing newlines around the rewrite so list and paragraph
breaks survive. Every byte outside the patch is kept: files are read and written
without newline translation. The patch must pass locate_patch.prose_span (exactly
once, in prose); exits 3 when it does not or the rewrite is empty, and
rewrite-md.sh then leaves FILE as it was. Runs on Python 3.9, the macOS system
python3.
"""

from __future__ import annotations

import sys

from locate_patch import prose_span, read


def main(path: str, patch_file: str, rewrite_file: str, out: str) -> int:
    content = read(path)
    patch = read(patch_file)
    rewrite = read(rewrite_file).strip("\r\n")
    start = prose_span(content, patch)
    if not rewrite or start is None:
        return 3
    lead = patch[: len(patch) - len(patch.lstrip("\r\n"))]
    trail = patch[len(patch.rstrip("\r\n")) :]
    new = content[:start] + lead + rewrite + trail + content[start + len(patch) :]
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:5]))

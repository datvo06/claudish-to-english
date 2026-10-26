"""Decide whether an Edit patch can be rewritten in place, for rewrite-md.sh.

    python3 locate_patch.py FILE PATCH_FILE

Exits 0 when the patch appears exactly once in FILE and sits in plain prose, and 3
otherwise. An Edit leaves new_string where old_string was, so a patch that appears
more than once has no known span. There is no Markdown parser on a bare macOS
Python, so the check is an allow-list that leans toward skipping, which only means
the fragment is not rewritten:

- every line of the paragraph block around the patch (out to the nearest blank
  lines) must be a prose line: no fence, no indentation of four columns or more
  (Markdown tab stops), and no line opening raw HTML or $$ math;
- the patch may not start or end inside an inline code span;
- nothing before that block may leave the YAML frontmatter, a fenced code block,
  or a multi-paragraph raw HTML block (pre, script, style, textarea, comment,
  processing instruction, declaration, CDATA) open.

Files are read without newline translation so CRLF documents compare byte for
byte. Runs on Python 3.9, the macOS system python3.
"""

from __future__ import annotations

import re
import sys

QUOTE = re.compile(r"^(?: {0,3}>[ \t]?)*")
LIST_MARKER = re.compile(r"^ {0,3}(?:[-+*]|\d{1,9}[.)])(?=[ \t]|$)")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
# Raw HTML blocks that can span blank lines. A pre, script, style or textarea block
# runs to its own closing tag: CommonMark ends it at any of the four, but a browser
# keeps the element open until its own end tag, and skipping more is the safe side.
LITERAL_TAG = re.compile(r"^ {0,3}<(pre|script|style|textarea)(?:[\s>]|$)", re.I)
HTML_BLOCKS = (
    (re.compile(r"^ {0,3}<!--"), re.compile(r"-->")),
    (re.compile(r"^ {0,3}<\?"), re.compile(r"\?>")),
    (re.compile(r"^ {0,3}<![A-Za-z]"), re.compile(r">")),
    (re.compile(r"^ {0,3}<!\[CDATA\["), re.compile(r"\]\]>")),
)


def read(path: str) -> str:
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def unquoted(line: str) -> str:
    return line[QUOTE.match(line).end() :]


def indent_columns(text: str) -> int:
    """Width of the leading whitespace, with tabs advancing to the next multiple of 4."""
    column = 0
    for char in text:
        if char == " ":
            column += 1
        elif char == "\t":
            column += 4 - column % 4
        else:
            break
    return column


def prose_line(line: str) -> bool:
    body = unquoted(line)
    if not body.strip():
        return True
    if indent_columns(body) >= 4:
        return False
    marker = LIST_MARKER.match(body)
    if marker:
        body = body[marker.end() :]
        if body.strip() and indent_columns(body) > 4:
            return False
    stripped = body.lstrip()
    return not (FENCE.match(body) or stripped.startswith("<") or stripped.startswith("$$"))


def raw_open_after(text: str) -> bool:
    """Whether a fenced code block or a multi-paragraph HTML block is open at the end."""
    fence: str | None = None
    html_end: re.Pattern[str] | None = None
    for line in text.splitlines():
        body = unquoted(line)
        if fence is not None:
            # Inside a fence a list marker is literal text, so it is not stripped:
            # a line such as "- ```" cannot close the block.
            match = FENCE.match(body)
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence) and not match.group(2).strip():
                fence = None
            continue
        marker = LIST_MARKER.match(body)
        content = body[marker.end() :].lstrip(" \t") if marker else body
        if html_end is not None:
            if html_end.search(line):
                html_end = None
            continue
        match = FENCE.match(content)
        if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
            fence = match.group(1)
            continue
        literal = LITERAL_TAG.match(content)
        if literal:
            end_tag = re.compile(rf"</{literal.group(1)}\s*>", re.I)
            if not end_tag.search(content[literal.end() :]):
                html_end = end_tag
            continue
        for start, end in HTML_BLOCKS:
            opened = start.match(content)
            if opened:
                if not end.search(content[opened.end() :]):
                    html_end = end
                break
    return fence is not None or html_end is not None


def frontmatter_end(content: str) -> int:
    """Offset just past leading YAML frontmatter, or 0 when there is none.

    The block opens with '---' on the first line and closes on a '---' or '...'
    line; an unclosed block counts as running to the end of the file.
    """
    lines = content.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        return 0
    offset = len(lines[0])
    for line in lines[1:]:
        offset += len(line)
        if line.rstrip("\r\n").rstrip() in ("---", "..."):
            return offset
    return len(content)


BLANK_LINE = re.compile(r"\n[ \t]*\r?\n")
BACKTICKS = re.compile(r"`+")


def code_spans(text: str) -> list[tuple[int, int]]:
    """Inline code spans in text: a backtick run up to the next run of the same length."""
    runs = [(m.start(), m.end()) for m in BACKTICKS.finditer(text)]
    spans: list[tuple[int, int]] = []
    i = 0
    while i < len(runs):
        width = runs[i][1] - runs[i][0]
        close = next((k for k in range(i + 1, len(runs)) if runs[k][1] - runs[k][0] == width), None)
        if close is None:
            i += 1
            continue
        spans.append((runs[i][0], runs[close][1]))
        i = close + 1
    return spans


def prose_span(content: str, patch: str) -> int | None:
    """Start of the patch when it appears exactly once inside a block of plain prose."""
    if not patch or content.count(patch) != 1:
        return None
    start = content.index(patch)
    end = start + len(patch)
    if start < frontmatter_end(content):
        return None
    before = [m.end() for m in BLANK_LINE.finditer(content, 0, start)]
    block_start = before[-1] if before else 0
    after = BLANK_LINE.search(content, end)
    block_end = after.start() if after else len(content)
    if raw_open_after(content[:block_start]):
        return None
    block = content[block_start:block_end]
    if not all(prose_line(line) for line in block.splitlines()):
        return None
    # A patch may hold whole code spans (the prompt keeps them verbatim), but it
    # may not start or end inside one, where the model would see code as prose.
    for span_start, span_end in code_spans(block):
        span_start, span_end = span_start + block_start, span_end + block_start
        if span_start < end and span_end > start and not (start <= span_start and span_end <= end):
            return None
    return start


if __name__ == "__main__":
    sys.exit(0 if prose_span(read(sys.argv[1]), read(sys.argv[2])) is not None else 3)

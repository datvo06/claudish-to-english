#!/bin/bash
# Drive rewrite-md.sh with synthetic Edit payloads (stub provider, no model calls):
#   bash tests/rewrite-md-edit.sh
set -u
hook="$(cd "$(dirname "$0")/.." && pwd)/rewrite-md.sh"
bash -n "$hook" && echo "syntax ok"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=1; fi; }
P="This is a fairly long new paragraph of prose that should clear the eighty character minimum for patches."
FILLER="An untouched paragraph stays exactly the same, and it is long enough that the whole document clears the two hundred character minimum for full rewrites."
FM="description: a long front matter description that is well past the eighty character minimum for a patch"

run() {  # run MODE FILE NEW_STRING [REPLACE_ALL]
  jq -nc --arg f "$2" --arg s "$3" --argjson r "${4:-false}" \
    '{hook_event_name:"PostToolUse", tool_name:"Edit", tool_input:{file_path:$f, new_string:$s, replace_all:$r}}' \
    | CLAUDISH_MD_DIR="$(dirname "$2")" CLAUDISH_MD_MODE="$1" CLAUDISH_STUB=1 TMPDIR="$(dirname "$2")" \
      CLAUDISH_OFF_FILE=/nonexistent CLAUDISH_NOTICE=0 bash "$hook" >/dev/null
}

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

printf '# Title\n\n%s\n\n%s\n' "$FILLER" "$P" > "$d/one.md"
run overwrite "$d/one.md" "$P"
check "overwrite: the one occurrence is rewritten" 'grep -q "STUB-SIMPLIFIED-PATCH.*$P" "$d/one.md"'
check "overwrite: the rest of the file is untouched" 'grep -qx "$FILLER" "$d/one.md"'

printf '# Title\n\n%s\n\n%s\n' "$P" "$P" > "$d/twice.md"; cp "$d/twice.md" "$d/twice.orig"
run overwrite "$d/twice.md" "$P"
check "overwrite: a patch found twice leaves the file alone" 'cmp -s "$d/twice.md" "$d/twice.orig"'

printf '# Title\n\n%s\n\n%s\n' "$FILLER" "$P" > "$d/all.md"; cp "$d/all.md" "$d/all.orig"
run overwrite "$d/all.md" "$P" true
check "overwrite: replace_all leaves the file alone" 'cmp -s "$d/all.md" "$d/all.orig"'

printf '# Title\n\n%s\n\n%s\n' "$FILLER" "$P" > "$d/sib.md"; cp "$d/sib.md" "$d/sib.orig"
run sibling "$d/sib.md" "$P"
check "sibling: the original stays untouched" 'cmp -s "$d/sib.md" "$d/sib.orig"'
check "sibling: the sibling copy is written" '[ -f "$d/sib.plain.md" ]'

NL="$P"$'\n\n'
printf '# Title\n\n%s\n\n- item one\n' "$P" > "$d/nl.md"
run overwrite "$d/nl.md" "$NL"
check "overwrite: a patch ending in blank lines keeps the list after it" 'tail -1 "$d/nl.md" | grep -qx -- "- item one" && grep -q "STUB-SIMPLIFIED-PATCH" "$d/nl.md"'

CODE="result = compute_the_answer(first_argument_value, second_argument_value, third_argument_value, fourth_argument)"
printf '# Title\n\n%s\n\n```python\n%s\n```\n' "$FILLER" "$CODE" > "$d/code.md"; cp "$d/code.md" "$d/code.orig"
run overwrite "$d/code.md" "$CODE"
check "overwrite: an edit inside a fenced code block is left alone" 'cmp -s "$d/code.md" "$d/code.orig"'

INNER="An inner example line that is long enough to clear the eighty character minimum for a patch rewrite."
printf '# Title\n\n%s\n\n````markdown\n```bash\n%s\n```\n````\n' "$FILLER" "$INNER" > "$d/nested.md"; cp "$d/nested.md" "$d/nested.orig"
run overwrite "$d/nested.md" "$INNER"
check "overwrite: an edit inside a four-backtick block holding a three-backtick example is left alone" 'cmp -s "$d/nested.md" "$d/nested.orig"'

printf '# Title\n\n%s\n\n~~~\n```\n%s\n~~~\n' "$FILLER" "$INNER" > "$d/tilde.md"; cp "$d/tilde.md" "$d/tilde.orig"
run overwrite "$d/tilde.md" "$INNER"
check "overwrite: an edit inside a tilde block holding a backtick line is left alone" 'cmp -s "$d/tilde.md" "$d/tilde.orig"'

printf '# Title\n\n%s\n\n> ```text\n> %s\n> ```\n' "$FILLER" "$INNER" > "$d/quote.md"; cp "$d/quote.md" "$d/quote.orig"
run overwrite "$d/quote.md" "$INNER"
check "overwrite: an edit inside a fenced block in a blockquote is left alone" 'cmp -s "$d/quote.md" "$d/quote.orig"'

printf '# Title\n\n%s\n\n- step one\n\n  ```bash\n  %s\n  ```\n' "$FILLER" "$INNER" > "$d/list.md"; cp "$d/list.md" "$d/list.orig"
run overwrite "$d/list.md" "$INNER"
check "overwrite: an edit inside a fenced block in a list item is left alone" 'cmp -s "$d/list.md" "$d/list.orig"'

printf '# Title\n\n%s\n\n    %s\n' "$FILLER" "$INNER" > "$d/indent.md"; cp "$d/indent.md" "$d/indent.orig"
run overwrite "$d/indent.md" "$INNER"
check "overwrite: an edit inside an indented code block is left alone" 'cmp -s "$d/indent.md" "$d/indent.orig"'

printf '# Title\n\n%s\n\n      %s\n' "$FILLER" "$INNER" > "$d/deep.md"; cp "$d/deep.md" "$d/deep.orig"
run overwrite "$d/deep.md" "$INNER"
check "overwrite: an edit in code indented six spaces is left alone" 'cmp -s "$d/deep.md" "$d/deep.orig"'

printf '# Title\n\n%s\n\n\t  %s\n' "$FILLER" "$INNER" > "$d/tab.md"; cp "$d/tab.md" "$d/tab.orig"
run overwrite "$d/tab.md" "$INNER"
check "overwrite: an edit in code indented with a tab and spaces is left alone" 'cmp -s "$d/tab.md" "$d/tab.orig"'

printf '# Title\n\n%s\n\n  \t%s\n' "$FILLER" "$INNER" > "$d/sptab.md"; cp "$d/sptab.md" "$d/sptab.orig"
run overwrite "$d/sptab.md" "$INNER"
check "overwrite: an edit in code indented with spaces then a tab is left alone" 'cmp -s "$d/sptab.md" "$d/sptab.orig"'

printf '# Title\n\n%s\n\n<pre>\n%s\n</pre>\n' "$FILLER" "$INNER" > "$d/pre.md"; cp "$d/pre.md" "$d/pre.orig"
run overwrite "$d/pre.md" "$INNER"
check "overwrite: an edit inside a multi-line <pre> block is left alone" 'cmp -s "$d/pre.md" "$d/pre.orig"'

printf '# Title\n\n%s\n\n<script>\n\n%s\n\n</script>\n' "$FILLER" "$INNER" > "$d/script.md"; cp "$d/script.md" "$d/script.orig"
run overwrite "$d/script.md" "$INNER"
check "overwrite: an edit inside a <script> block with blank lines is left alone" 'cmp -s "$d/script.md" "$d/script.orig"'

printf '# Title\n\n%s\n\n<!--\n\n%s\n\n-->\n' "$FILLER" "$INNER" > "$d/comment.md"; cp "$d/comment.md" "$d/comment.orig"
run overwrite "$d/comment.md" "$INNER"
check "overwrite: an edit inside a multi-line HTML comment is left alone" 'cmp -s "$d/comment.md" "$d/comment.orig"'

printf '# Title\n\n%s\n\n<div>\n%s\n</div>\n' "$FILLER" "$INNER" > "$d/div.md"; cp "$d/div.md" "$d/div.orig"
run overwrite "$d/div.md" "$INNER"
check "overwrite: an edit inside a raw <div> block is left alone" 'cmp -s "$d/div.md" "$d/div.orig"'

printf '# Title\n\n%s\n\n```text\n- ```\n\n%s\n```\n' "$FILLER" "$INNER" > "$d/listfence.md"; cp "$d/listfence.md" "$d/listfence.orig"
run overwrite "$d/listfence.md" "$INNER"
check "overwrite: a literal list-marker fence line inside code does not end the block" 'cmp -s "$d/listfence.md" "$d/listfence.orig"'

IDENT="configure_the_rewrite_pipeline_with_a_very_long_identifier_name_that_clears_the_minimum_length"
printf '# Title\n\n%s\n\nCall `%s` before the first rewrite.\n' "$FILLER" "$IDENT" > "$d/inline.md"; cp "$d/inline.md" "$d/inline.orig"
run overwrite "$d/inline.md" "$IDENT"
check "overwrite: an edit inside inline code is left alone" 'cmp -s "$d/inline.md" "$d/inline.orig"'

printf '# Title\n\n%s\n\nCall ``%s`` before\nthe first rewrite.\n' "$FILLER" "$IDENT" > "$d/inline2.md"; cp "$d/inline2.md" "$d/inline2.orig"
run overwrite "$d/inline2.md" "$IDENT"
check "overwrite: an edit inside double-backtick inline code is left alone" 'cmp -s "$d/inline2.md" "$d/inline2.orig"'

WITH_CODE="Call \`setup()\` first, then this paragraph of prose is long enough to clear the eighty character minimum."
printf '# Title\n\n%s\n\n%s\n' "$FILLER" "$WITH_CODE" > "$d/whole.md"
run overwrite "$d/whole.md" "$WITH_CODE"
check "overwrite: a patch holding a whole inline code span is rewritten" 'grep -q "STUB-SIMPLIFIED-PATCH" "$d/whole.md"'

printf '# Title\n\n%s\n\n<pre>\n</style>\n\n%s\n\n</pre>\n' "$FILLER" "$INNER" > "$d/mismatch.md"; cp "$d/mismatch.md" "$d/mismatch.orig"
run overwrite "$d/mismatch.md" "$INNER"
check "overwrite: a mismatched closing tag does not end a <pre> block" 'cmp -s "$d/mismatch.md" "$d/mismatch.orig"'

printf '# Title\n\n<pre>\ncode\n</pre>\n\n%s\n' "$P" > "$d/afterpre.md"
run overwrite "$d/afterpre.md" "$P"
check "overwrite: prose after a closed <pre> block is rewritten" 'grep -q "STUB-SIMPLIFIED-PATCH" "$d/afterpre.md"'

printf '# Title\n\n%s\n\n<pre>%s</pre>\n' "$FILLER" "$INNER" > "$d/html.md"; cp "$d/html.md" "$d/html.orig"
run overwrite "$d/html.md" "$INNER"
check "overwrite: an edit on a raw HTML line is left alone" 'cmp -s "$d/html.md" "$d/html.orig"'

printf -- '---\n%s\n...\n\n# Title\n\n%s\n' "$FM" "$FILLER" > "$d/dots.md"; cp "$d/dots.md" "$d/dots.orig"
run overwrite "$d/dots.md" "$FM"
check "overwrite: frontmatter closed with ... is left alone" 'cmp -s "$d/dots.md" "$d/dots.orig"'

printf -- '---\n%s\n\n# Title\n\n%s\n' "$FM" "$P" > "$d/open.md"; cp "$d/open.md" "$d/open.orig"
run overwrite "$d/open.md" "$P"
check "overwrite: nothing is rewritten after an unclosed frontmatter opener" 'cmp -s "$d/open.md" "$d/open.orig"'

printf '# Title\n\n%s\n\n%s\n' "$FILLER" "$P" > "$d/notice.md"
notice=$(jq -nc --arg f "$d/notice.md" --arg s "$P" \
  '{hook_event_name:"PostToolUse", tool_name:"Edit", session_id:"notice-test", tool_input:{file_path:$f, new_string:$s}}' \
  | CLAUDISH_MD_DIR="$d" CLAUDISH_MD_MODE=overwrite CLAUDISH_STUB=1 TMPDIR="$d" FALLBACK_NOTICE="the fallback provider wrote this" \
    CLAUDISH_OFF_FILE=/nonexistent CLAUDISH_NOTICE=1 bash "$hook")
check "overwrite: a successful Edit emits the shared once-per-session notice" 'printf "%s" "$notice" | jq -e ".systemMessage | test(\"fallback provider\")" >/dev/null'

printf '# Title\n\n````\n```\ncode\n````\n\n%s\n' "$P" > "$d/after.md"
run overwrite "$d/after.md" "$P"
check "overwrite: prose after closed nested blocks is rewritten" 'grep -q "STUB-SIMPLIFIED-PATCH" "$d/after.md"'

if [ -x /usr/bin/python3 ]; then
  printf '# Title\n\n%s\n\n%s\n' "$FILLER" "$P" > "$d/sys.md"
  PATH="/usr/bin:/bin:$PATH" run overwrite "$d/sys.md" "$P"
  check "overwrite: works with the macOS system python3 ($(/usr/bin/python3 -V 2>&1))" 'grep -q "STUB-SIMPLIFIED-PATCH" "$d/sys.md"'
fi

printf -- '---\n%s\n---\n\n# Title\n\n%s\n' "$FM" "$FILLER" > "$d/fm.md"; cp "$d/fm.md" "$d/fm.orig"
run overwrite "$d/fm.md" "$FM"
check "overwrite: an edit inside the frontmatter is left alone" 'cmp -s "$d/fm.md" "$d/fm.orig"'

printf '# Title\r\n\r\n%s\r\n\r\n%s\r\n' "$FILLER" "$P" > "$d/crlf.md"
crlf_before=$(grep -c $'\r$' "$d/crlf.md")
run overwrite "$d/crlf.md" "$P"
check "overwrite: a CRLF document gets the rewrite" 'grep -q "STUB-SIMPLIFIED-PATCH" "$d/crlf.md"'
check "overwrite: a CRLF document keeps every line ending" '[ "$(grep -c $'"'"'\r$'"'"' "$d/crlf.md")" -eq "$crlf_before" ]'

for p in 'not json' '' '{"tool_name":"Edit"}'; do
  out=$(printf '%s' "$p" | CLAUDISH_MD_DIR="$d" bash "$hook"); rc=$?
  check "fails open on [$p]" '[ "$rc" -eq 0 ] && [ -z "$out" ]'
done
exit "$fails"

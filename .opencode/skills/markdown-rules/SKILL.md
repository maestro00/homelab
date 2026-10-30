---
name: markdown-rules
description: >
  Tay's markdown formatting rules for every file written in this repo or its
  skills. Use when writing, editing, or reviewing any Markdown (.md) file —
  READMEs, skill docs, SESSION_SUMMARY, issue bodies, workflow docs, or commit
  message bodies. Applies to all documentation and inline markdown. Trigger on
  any mention of "markdown", "readme", "documentation", or "write docs".
---

# Markdown Rules

Formatting conventions for every `.md` file. Follow these exactly — they make
docs consistent and diffable.

## Headings

- ATX style only (`#`), never Setext (`===`/`---` underlines).
- One `#` H1 per file, matching the file's topic.
- Hierarchy must not skip levels: `#` → `##` → `###` in order.
- Sentence case, no trailing colons, no punctuation after the heading text.

## Structure

- Blank line before and after every heading, list, and code block.
- Lists: `-` bullets, numbered `1.` only for ordered steps. Sub-lists indent 2 spaces.
- Break long paragraphs at a readable line width (~80 chars) at natural points.
- Use `---` horizontal rules sparingly, only between major sections.
- Keep lines under 80 characters (MD013). Hard-wrap prose at natural points.

## Code & commands

- Fenced code blocks with a language tag (MD040): ` ```bash `, ` ```yaml `,
  ` ```text `, ` ```caddyfile `. Never leave a fence without a language.
- Surround every fenced block with blank lines (MD031) — never glue a block
  directly to a paragraph or list item.
- Inline code with single backticks for files, paths, commands, flags, values.
  No spaces inside the backticks (MD038).
- Shell prompts are written as `$` inside bash blocks; omit it for pure
  copy-paste. Never wrap a bare command in prose — use inline code or a block.

## Tables

- Pipe tables for tabular data. Header row + separator row always (MD055).
- Align all pipes to the widest cell in each column, header included (MD060,
  style `aligned`). Left-align text; pad with spaces, not tabs.
- Keep table rows under 80 chars; split wide columns or move long prose into a
  following note.

## Emphasis & links

- `**bold**` for key terms, never `*asterisks*` for emphasis.
- Links: `[text](path-or-url)`. Use relative paths for in-repo files.
- Prefer linking over inline absolute file paths.

## Notes & callouts

- Use blockquote (`>`) for warnings/caveats, not bold text.
- One blank line before and after the blockquote.

## General

- No emojis unless explicitly requested.
- No trailing whitespace. One newline at end of file.
- Keep each file focused; link to other docs instead of duplicating content.

# Portfolio Redesign — Contact Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `portfolio.yukselcloud.com` as the taste-skill `contact-sheet` direction (sheet seed 1418059130) and deploy it, so the page is an archive drawer of the systems its owner actually runs.

**Architecture:** One static `index.html` with inline CSS/JS, rebuilt from zero in the gitignored source dir, gated by the taste-skill scripts (lint + real-browser inspector + screenshot critique rounds), then regenerated into `configmap.yaml` and shipped through the existing Forgejo deploy workflow. Found raster pictures ride in a separate `binaryData` ConfigMap mounted at `/img`.

**Tech Stack:** HTML/CSS/vanilla JS, Archivo (Google Fonts), taste-skill scripts (Node 22 + Playwright Chromium), kubectl + Forgejo Actions. No frameworks, no build tooling.

**Spec:** `docs/superpowers/specs/2026-10-31-portfolio-redesign-design.md` — read it fully before Task 2; it carries the idea sentence, live thing, palette/type decisions and the section map. Direction sheet: `node ~/.config/opencode/skills/taste-skill/scripts/draw.mjs --show`.

## Global Constraints

- `SK` = `~/.config/opencode/skills/taste-skill`; project root = `/home/taylan/Documents/projects/homelab`; page source = `k3s-ha-cluster/portfolio/html/index.html` (gitignored; never committed).
- One HTML file, inline CSS/JS, no framework, no bundler. Google Fonts link only.
- Type: Archivo 400/600 only, ≤5 size steps, body ≥16px, nothing under 13px, no mono outside real `<pre><code>`.
- Palette verbatim from spec §Colour (`#1c1c1c/#262626/#f1f1ef/#9a9b96/#8fa68e`, one `#c8c5ba` field used once); accent only on the primary action and active states.
- Banned everywhere: gradients, glows, shadows at rest, glass/backdrop-blur, emoji, eyebrows, index numbers, hairline rules, card grids of identical boxes, violet, cream+terracotta, `transition: all`.
- Disclosure line: never node names, hostnames other than already-public ones, IPs, ports, version strings, live health or pod counts; topology shown **as designed** (3 control planes + 2 workers); no invented clients, quotes, logos or statistics.
- Imagery floor: ≥4 real raster pictures (found via `$SK/scripts/assets.mjs`, downloaded, credited in footer, `alt` + `width`/`height` set, `loading="lazy"` except hero) and ≥20 sheet frames; SVG drawings don't count toward the floor.
- Size ceiling: every ConfigMap ≤1 MiB. `html/` and `img/` stay gitignored; committed artifacts are `configmap.yaml`, `assets-configmap.yaml`, `deployment.yaml`, `README.md`.
- No push until Task 8: any commit touching `k3s-ha-cluster/portfolio/**` deploys publicly.
- Accessibility: every control keyboard-operable in reading order with visible focus and an accessible name; contrast ≥4.5:1; `prefers-reduced-motion` keeps all content, drops travel; page readable with JS off.
- The gate commands for every task: `node $SK/scripts/lint.mjs <file>` → 0 findings; `node $SK/scripts/inspect.mjs <path> --out .taste-skill/<name>` → 0 FAIL, every WARN defended or fixed.

## Review Focus

Failure modes no task's gate fully measures — pin each with the named check in its task:

- **JS disabled** → every frame-run's plain + infra line is still in the DOM and readable in order (Task 5 check: disable script block, inspect screenshots).
- **`prefers-reduced-motion`** → entrances must never leave content invisible (Task 7 check: reduced-motion screenshot at 1440 shows all sections opaque).
- **Google Fonts blocked** (corporate networks) → system fallback stack keeps lines unbroken and no layout shift bug; verify by stripping the link (Task 4 check).
- **ConfigMap overflow** → `kubectl apply` fails mid-workflow and the site serves the old page silently; enforce the byte budget before commit (Task 8 check).
- **390 px phone** → the strip bleeds and scrolls, spines reflow as a wrapped paragraph, zero horizontal page overflow (Task 5 + 7 inspect at 390).

---

### Task 1: Gate harness + baseline

**Files:**
- Create: `.taste-skill/before/` (outputs), `.taste-skill/notes.md`
- Modify: none in git

**Interfaces:**
- Produces: verified commands `node $SK/scripts/inspect.mjs <target>` and `node $SK/scripts/lint.mjs <target>` that run on this machine, for every later task.

- [ ] **Step 1:** Confirm Playwright Chromium landed (`~/.cache/ms-playwright/chromium-*/chrome-linux/chrome`). Check how `$SK/scripts/lib/cdp.mjs` discovers browsers (grep for executable names / env overrides); make discovery find it — env var or a user-local `chromium` symlink on PATH — **without editing the skill** if possible.
- [ ] **Step 2:** `node $SK/scripts/inspect.mjs k3s-ha-cluster/portfolio/html/index.html --out .taste-skill/before` → screenshots at 1440/768/390 exist; record its FAIL list (the slop audit in meter form) in `.taste-skill/notes.md`.
- [ ] **Step 3:** `node $SK/scripts/lint.mjs k3s-ha-cluster/portfolio/html/index.html` → record findings count in notes.

### Task 2: Copy deck (before any markup)

**Files:**
- Create: `.taste-skill/copy-deck.md`

**Interfaces:**
- Consumes: spec section map; the current page's facts (jobs, bullets, skills, education, links).
- Produces: exact final wording every later task types in verbatim.

- [ ] **Step 1:** Read `$SK/references/copy.md` §1–2.
- [ ] **Step 2:** Write the deck: claim+proof line per section; hero name sentence (≤60 chars, ≤2 lines at every width); about paragraph (5 lines plain English for recruiters) + side facts; proof columns — every skill name, grouped by kind, ≤30 entries; showcase notes for the five cluster fragments; work spines — all 5 jobs + 4 personal projects + 3 degrees with discipline tags; list rows — role · company left, dates right, tabular; contact statement (reuse his own line: "Open to interesting problems in infrastructure, distributed systems, and backend engineering"), city + reply time; footer credits scaffold + the self-hosted line as thesis.
- [ ] **Step 3:** Self-check: no invented proof anywhere; any sample detail (e.g. media-stack service names) marked `[confirm]` in the deck and listed for the report. Doctest style check: every headline ≤32 chars — grep the deck and count.

### Task 3: Picture hunt + budget

**Files:**
- Create: `k3s-ha-cluster/portfolio/img/` (gitignored), `.taste-skill/credits.md`

**Interfaces:**
- Produces: `/img/<file>` names the HTML will reference (Task 4/5) — final list recorded in credits.md.

- [ ] **Step 1:** Search open collections with `node $SK/scripts/assets.mjs` from the inventory, not the category: `"helsinki harbour"`, `"helsinki old map"`, `"finland archipelago postcard"`, `"telephone exchange 1920s"`, `"telegraph"`, plus `--video "helsinki"`. Pick ≥4 stills + 1 clip for an honest muted loop.
- [ ] **Step 2:** `--get` each; keep total raster payload <600 KB (resize/recompress — prefer source thumbnail URLs at ≤1600 px wide, or `cwebp`/ImageMagick if present).
- [ ] **Step 3:** `node $SK/scripts/assets.mjs --credits > .taste-skill/credits.md`; verify each entry has title, creator, licence, source page.

### Task 4: Skeleton — tokens, frame, hero strip

**Files:**
- Modify (gitignored): `k3s-ha-cluster/portfolio/html/index.html` (overwrite from scratch)

**Interfaces:**
- Consumes: spec palette/type values, deck hero wording, `/img` list.
- Produces: CSS custom-property names (`--bg --surface --ink --muted --accent --accent-ink --field-1 --field-1-ink` + 4 type steps) that Task 5 uses; the strip's frame markup pattern.

- [ ] **Step 1:** Head: charset/viewport/title, Archivo 400;600 link with `font-display: swap`, fallback stack `'Archivo', system-ui, sans-serif` set in the token so a blocked font can't break layout.
- [ ] **Step 2:** Tokens + reset from spec values; 12-col grid; one pair of equal outer margins; square corners on media; one button shape (≥44 px, solid fill, no radius) — house rules.
- [ ] **Step 3:** Hero: name as `h1` at display size across the top (6–9vw, Archivo 400, tracking −0.02em); corner blocks who/what/where-to-reach at 14–16 px; lit strip across the middle — flex row, ~32 vh frames, natural widths, 10 px gaps, edge-bleed, `overflow-x: auto` + `scroll-snap`, centre-lit brightness treatment, ≥11 frames (found pictures + 2–3 interface fragments from Task 5 pattern early); bottom: one real button + one link, per adjusted blueprint.
- [ ] **Step 4:** Phone: strip 46 vh single row, corners restack per blueprint. Run gate commands (constraints) + screenshot; fonts-blocked check: comment out the link once, screenshot, confirm no broken layout.

### Task 5: Sections + the live sheet

**Files:**
- Modify: `k3s-ha-cluster/portfolio/html/index.html`

**Interfaces:**
- Consumes: copy deck wording (verbatim), tokens, `/img` files.
- Produces: section ids `#about #skills #cluster #index #record #contact` for the nav links; `.data-ui` fragments pattern.

- [ ] **Step 1:** about: a heading that names it per the house rule (the sheet's "no heading" line loses to `inspect.mjs`'s untitled-section FAIL — settle as the section's plain title in the same small type) + side-facts column at the 34% line + the 5-line paragraph → proof: skills as plain names in `columns: 4`, each kind starting a column in muted ink, no boxes.
- [ ] **Step 2:** showcase #cluster: heading + link + notes in the left column; run of five `data-ui` HTML fragments at one row height — (a) control-plane table rendered as "control plane ×3 · Ready / worker ×2 · Ready" with **no node names**, (b) Beszel-style panel with plausible (labelled example) metrics, (c) Longhorn volume rows, (d) route table of public hostnames only, (e) Forgejo Actions run of *this page's own deploy* — steps taken from `.forgejo/workflows/deploy-portfolio.yaml`; one lifted frame at 2.2× aligned bottom.
- [ ] **Step 3:** work #index: book-spine row — every job/project/degree, discipline tinted from 4 palette colours, ink/muted contrast for active state (no fading per sheet adjustment), each spine a real link; phone reflow rule. list #record: two-ended rows (role · company ← dates →, tabular figures), groups "Employment" / "Education" opened by a plain soft-ink word. contact #contact: statement ≤36 px, Helsinki picture in the square slot, email + one link underlined, city + reply time.
- [ ] **Step 4:** Live sheet inspect interaction: hover/focus/click a run dims siblings (ink→muted, not transparency), one fixed slot shows that run's plain line + infra line; the same lines exist per run statically in the DOM (JS-off check: `grep -c` each run's description outside the slot, and screenshot with the script block commented).
- [ ] **Step 5:** Footer: credits from credits.md, "self-hosted on the cluster above" as thesis line. Frame audit: ≥20 frames, ≥4 real rasters, alt/width/height everywhere.
- [ ] **Step 6:** Gate at all three widths → 0 FAIL; defend or fix every WARN. Review Focus lines 1, 3, 5 checked here.

### Task 6: Look rounds

**Files:**
- Create: `.taste-skill/critique-1.md` (…-3.md), `.taste-skill/after/`

- [ ] **Step 1:** Read `$SK/references/critique.md`; open every screenshot from the last inspect (all three widths, every screen).
- [ ] **Step 2:** Write the critique in its format with the score; fix the top three problems in the page; re-run inspect; look again. Repeat ≤3 rounds or until juror score stops improving — record rounds and the final score for the report.

### Task 7: Motion layer

**Files:**
- Modify: `k3s-ha-cluster/portfolio/html/index.html`

- [ ] **Step 1:** Signature = the drag row (native scroll-snap, no carousel code). Add: per-section entrance (heading → text → picture, 60–90 ms stagger, 16–32 px rise, triggered once); feedback on every spine, link, button, frame (colour/surface change only, no `transition: all`, transform/opacity only); one moving picture (found clip muted loop with poster, else slow scroll-linked move on the hero photo — pick one).
- [ ] **Step 2:** Every move has a `prefers-reduced-motion` fallback that keeps content. Re-run inspect: motion count ≥8 moving elements, 0 FAIL; screenshot with reduced-motion emulation (Review Focus line 2) and re-open every width to confirm nothing stayed hidden.

### Task 8: Ship it live

**Files:**
- Modify: `.gitignore` (add `.taste-skill/`, `k3s-ha-cluster/portfolio/img/`)
- Create: `k3s-ha-cluster/portfolio/assets-configmap.yaml`
- Modify: `k3s-ha-cluster/portfolio/deployment.yaml` (second volume `portfolio-assets`, mount `/usr/share/nginx/html/img`, `optional: false`)
- Modify: `k3s-ha-cluster/portfolio/configmap.yaml` (regenerated from `html/`)
- Modify: `k3s-ha-cluster/portfolio/README.md` (update-workflow section: edit `html/` + `img/`, run `deploy.sh`; fix the stale `demo.yukselcloud.com` line to `portfolio.yukselcloud.com`)

- [ ] **Step 1:** Size gate (Review Focus line 4): page ≤ ~900 KB; `img/` total <600 KB; `kubectl create configmap portfolio-html --from-file=k3s-ha-cluster/portfolio/html/ -n portfolio --dry-run=client -o yaml` output <1 MiB (same for assets via `--from-file=k3s-ha-cluster/portfolio/img/`); patch metadata (name/namespace/labels) to match the current committed map.
- [ ] **Step 2:** Commit A: gitignore + assets-configmap.yaml + deployment.yaml + README. `kubectl -n portfolio apply` the assets map and deployment; `kubectl -n portfolio rollout status deployment/portfolio-site --timeout=90s`; site still serves the old page (expected — configmap unchanged).
- [ ] **Step 3:** Commit B: regenerated configmap.yaml → push triggers the `deploy-portfolio` workflow; watch it go (`act` alternative: `kubectl -n portfolio rollout status`), then verify live: `curl -sI https://portfolio.yukselcloud.com` 200; run `inspect.mjs https://portfolio.yukselcloud.com` against the **production URL** (skill step 7: inspect what the visitor receives) → 0 FAIL.
- [ ] **Step 4:** Final report per SKILL.md step 10: direction name + seed 1418059130, redraws (none; three settled disagreements listed), idea sentence, live thing, final critique scores, every found picture + licence and where credits sit, which frames are HTML reconstructions, all `[confirm]` sample content needing the owner's eye. Deliver the URL: "click it."
- [ ] **Step 5:** Rollback note in README: `git revert <B>` redeploys the previous page via the same workflow.

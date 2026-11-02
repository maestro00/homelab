# Portfolio redesign — The Contact Sheet

Date: 2026-10-31 · Status: approved by owner 2026-10-31
Direction sheet: taste-skill `contact-sheet`, seed 1418059130 (saved in `.taste-skill/direction.json`)

## Intent and the why

`portfolio.yukselcloud.com` is a single static HTML page served by the homelab itself
(ConfigMap → nginx pod → Caddy, deployed by a Forgejo Actions workflow). Today it wears
the standard AI-portfolio costume: cyan/indigo gradients, glass blur, emoji icons,
`01 / about` numbering, a centered column of identical cards. Swap the name for anyone
else's and it still fits — the failing test both installed skills (unslop, taste-skill)
run on every page.

Yusuf Taylan Yuksel's real story is the opposite of generic: he operates his own cloud —
a K3s HA cluster on Proxmox (3 control planes, 2 workers, Longhorn, MetalLB, Caddy,
Authelia, Forgejo GitOps, Beszel, Uptime Kuma, an Arr media stack, plus apps he built:
OpenGym, translator, telegram-agent) — and **this page is served by that cluster and
deployed by his own pipeline**. The redesign makes the page itself evidence of that.

Audience (owner's words): infra people who want proof and depth, **and** recruiters who
must understand who/what/how-to-reach in five seconds.

## Goals

- A page only this person could have: every fact from his real systems (the "inventory").
- First screen answers who + what + reach, in plain words, with no domain knowledge needed.
- Proof over claims: real interface reconstructions and true facts; nothing invented.
- Pass the taste-skill gate (lint.mjs + inspect.mjs or documented fallback) and the
  unslop checklist: quiet chrome, one accent, no emoji, no gradients, no glass, no
  shadows at rest, 4px rhythm, one icon language.
- Keep the deploy path working end-to-end (html/ → configmap → kubectl apply / workflow).

## Non-goals

- No framework or build-toolchain migration; it stays one HTML file with inline CSS/JS.
- No live calls from the browser into private cluster services (Authelia is in front of
  all of them; the page must not break or leak).
- No multi-page site, no CMS, no SEO project.
- Career facts and history are not rewritten — only their form changes.

## Anti-goals

- The page reads as "AI-redesigned": any banned tell returning in a new costume.
- Thin-out: a stripped page that lost ornament and gained nothing. Richness comes from
  scale, density of real frames, and real pictures — not from decoration.
- An infra demo that hides the human; a recruiter must not need a tooltip to understand
  the first screen.

## Constraints

- Single `index.html`, Google Fonts via link; total served payload small. ConfigMaps cap
  at 1 MiB, so real raster photographs live in a **separate `portfolio-assets`
  ConfigMap** (`binaryData`, mounted under `/img`); interface fragments are pure HTML
  (they carry `data-ui`, as the inspector's rules require).
- `k3s-ha-cluster/portfolio/html/` is gitignored; the committed artifact is
  `configmap.yaml`. A tiny regeneration step (`kubectl create configmap --dry-run=client
  -o yaml` from `html/`, plus the assets map from `img/`) becomes the documented update
  path, matching the README's "or regenerate it from html/".
- taste-skill floor: ≥20–24 sheet frames and ≥4 real raster pictures (open collections,
  downloaded into the project, credited in the footer). SVG drawings don't count toward
  the floor.
- The inspector needs Chromium. This machine has Firefox + Opera only. Either install
  chromium (owner's call) or ship with lint.mjs + manual screenshots and say so.
- Cluster facts must stay plausible for a public page (see open question 3).

## Approaches

1. **Polish mode (unslop craft pass on today's layout).** Cheapest; zero art direction.
   Rejected: the centered 900px identical-card column is itself the template — a polish
   pass can't clear the name-swap test.
2. **Full art-directed rebuild via taste-skill** — **chosen by the owner.** Within it the
   draw dealt three directions: `type-only-statement` (strong voice, but needs pictures
   he doesn't own); `quiet-instrument` (matches "instruments, night shifts", but a
   whisper buries his real advantage: volume of running systems); **`contact-sheet`** —
   chosen because its form *is* his material: strict rows of small frames where each
   frame is a system he actually runs. Trades: most work, must honestly fill 24+ frames.
3. **Rebuild with a new stack + live cluster APIs.** Rejected by the non-goal above and
   adds ops risk for no recruiting gain.

## The design (decisions as taken)

**Idea sentence:** On this page, the systems he actually runs become an archive drawer —
and one frame is the pipeline that deploys this very page.
*Competitor test:* another engineer's sheet has different frames; the self-deploying
page belongs only to a person who owns the cluster serving it.

**The one live thing:** the sheet inspect. Hover/tap a run of frames dims the others and
one fixed slot shows that system's plain-English line for recruiters ("what it does for
non-engineers") plus one infra line ("stack, namespace, one true fact"). Native to the
direction, thumb-sized, works without scripts (all runs' titles and lines are in the DOM
in reading order).

**Type:** Archivo 400/600 only (no mono outside real code, no Inter). Name at display
size across the top of the first screen (direction §2 outranks hero §6's 14px corner —
recorded as a settled disagreement); four size steps max.

**Colour:** charcoal ground `#1c1c1c`, surface `#262626`, ink `#f1f1ef`, muted `#9a9b96`,
**one** sage accent `#8fa68e` (primary action + active states only), one pale-concrete
field `#c8c5ba` used once. No gradients, no glows; surfaces step by tone, not hairlines.

**Frame:** one pair of equal outer margins (16–20px at the strip, larger inside text
columns per blueprints), 12-column grid, square corners on media, one button shape,
one radius.

**Sections (order and what goes in them):**

1. **Hero strip** — name + who/what/contact blocks at the top; a horizontally dragged
   strip of his running systems' frames across the middle (signature move); one
   primary action (email as a real button), one secondary link (LinkedIn/GitHub).
2. **About** — side facts (Helsinki · Ericsson · 3 degrees / 5 countries · since 2022)
   in the left 160px column; a five-line plain-language paragraph from the 34% line.
3. **Proof (skills)** — plain names in 4 text columns, each kind opening its column in
   soft ink: Infrastructure, Languages, Data & Storage, Security & GitOps.
4. **Showcase — The Cluster** — frame run of the cluster itself: k3s HA control-plane
   fragment, Beszel-style panel, Longhorn volumes list, MetalLB/Caddy route table,
   the deploy-pipeline run. One lifted frame (~2.2×) showing the live inspect detail;
   short notes at the left column.
5. **Work — book-spine index** — every job and project as one vertical spine: Ericsson,
   Templari, Tradenet, Mobilitypay, Częstochowa research, OpenGym, translator,
   telegram-agent, homelab. Discipline tinted by background from four palette steps.
   Full-ink/muted contrast instead of fading (sheet adjustment).
6. **List — Employment & Education rows** — two-ended rows (role + company left, dates
   right, tabular figures); three degrees as a second group. This carries what the
   removed stat theater ("4+ years") used to hint at.
7. **Contact band** — a ≤36px statement ("open to infrastructure and platform problems"
   in his words), a real Helsinki picture in the portrait slot, email + one link, city
   and reply time.

**Imagery order:** HTML interface fragments (his own product, `data-ui`) for the sheet;
4–6 real rasters via `assets.mjs` — Helsinki harbour/postcards, an old map of Finland,
archive tech/telephony plates — downloaded to `img/`, credited in the footer; one muted
loop video if an honest clip exists. Picsum dealt photos are *not* used (real collected
pictures outrank them; the floor is met honestly).

**Motion:** signature drag row (native scroll-snap); staggered entrance per section;
press/hover feedback on every control; ≥8 visibly moving elements; full
`prefers-reduced-motion` fallbacks.

**What is deliberately dropped from the current page:** the theme toggle (see open
question 1), gradient glows, glass blur, emoji icons, `01/02` numbering, uppercase
tracked labels, pill tags, stat counters, per-card scroll choreography, `// hello world`.
Content kept: all jobs, bullets (re-cast), skills, education, links, footer's
self-hosted line — which becomes the page's thesis instead of a caption.

## Left to the builder

- The full copy deck (written before markup, per the run), final frame list per run,
  chosen found pictures + credits, exact sizes under the ConfigMap cap, the
  regeneration script (a `deploy.sh` next to the manifests is fine), README/workflow
  touch-up, and the gate rounds.

## Owner decisions (2026-10-31)

1. **Dark-only, toggle dropped:** approved.
2. **Chromium:** approved — install via `npx playwright install chromium`.
3. **Go-live:** owner wants the finished page deployed and clickable at
   portfolio.yukselcloud.com at the end of this work; deploy commit is in-scope.
4. **Disclosure line:** approved (stack names, never node names/IPs/ports/versions).
   `infra-pi` is a *temporarily disabled* spare control plane — current cluster
   state is transient and never publishable content; the page shows the topology
   **as designed (3 CP + 2 workers)**, nothing about live health or node counts
   beyond what is permanent.

## Outcome (2026-11-02)

Shipped, then rejected by the owner on first read: "I really didn't like the ui at all.
I would rather have something simple, like the previous one and have readable content…
so wide page and not user friendly. simpler page is better."

The previous page was restored from git (`7c7f3cc^`) and redeployed. The contact-sheet
build remains in history at commit `7c7f3cc` if it is ever revisited; the lesson recorded
here is the scope one: an art-directed full rebuild was more than this page wanted.

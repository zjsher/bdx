---
name: care
description: Inject the "what you care about" index - a terse list of named failure/quality anchors across software (bad inputs, races, instance death, unbounded growth, tenancy, time, money, deps failing, seams...) - to widen the active agent's attention before implementing or reviewing. The generic tier under .claude/self-check.md - static priors that cover day one in any repo. Point it at a custom index (a .md path, or a name resolved from $AGENT_HOME/care/) to swap the built-in list for a domain-specific one. Use before a review pass, a thicken run, or any moment you want the blind-spot lens loaded. It widens noticing only - review findings still need the full finding-contract, and implementation-side concerns go to the Deferred list, never into unasked code.
user-invocable: true
argument-hint: [area: data|resilience|scale|security|design|ops] [custom index: path/to/index.md | <name> in $AGENT_HOME/care/]
---

# care

Attention is the scarce resource. An agent's bias is shaped by what it has generated and read so far - the concern it never names is the one it never checks. This skill is pure context injection: load the index below and the categories become fireable. No voice, no persona, no report - just the vocabulary of things good software worries about, appended to working memory. (A persona supplies tone _and_ what-they-notice; this is the what-they-notice, generic, without the voice.)

## Standing rules (the index is a lens, not a license)

1. **Widen the search, never lower the bar.** In review, an index-prompted candidate is still bound by the full finding contract - CONFIRMED needs a red repro, trace-only is PLAUSIBLE. An anchor is a place to look, not evidence.
2. **Notice and name, never build.** In implementation (skeleton/slice), a noticed concern flows to the Deferred list or the ledger, not into the diff. The anti-gold-plating guard binds exactly as before - an index anchor is precisely the kind of principled-feeling mid-slice impulse that guard exists to catch.
3. **Earned beats generic.** `.claude/self-check.md` is this repo's evidence of what actually goes wrong here; a hit there is a strong CONFIRMED signal. A hit here is a prior. When they compete for attention, the repo's list wins.
4. **No report on invocation.** Loading the lens is the whole act. Acknowledge in one line and continue the active task with the index in mind; if nothing is active, just confirm it's loaded.

## Arguments

Resolve `$ARGUMENTS` in this order:

1. **Empty** -> load the built-in index below, one-line acknowledgment.
2. **An area name** (`data`, `resilience`, `scale`, `security`, `design`, `ops`) -> load the built-in index and echo that section's anchors verbatim after loading - saying them again is what sharpens attention there.
3. **A path** (contains `/` or ends in `.md`, and the file exists) -> **read that file and inject it as the index instead of the built-in one.** The custom file replaces the built-in list entirely; close the injection with `== APPENDED THE "<filename>" INDEX ==` so the swap is visible.
4. **Any other word** -> try `$AGENT_HOME/care/<word>.md` (the saved-index convention, mirroring `$AGENT_HOME/personas/`). Found -> inject as in 3. Not found -> say so and fall back to the built-in index; never silently guess.

Custom index files are plain markdown - whatever anchors the domain needs (a frontend index, a data-pipeline index, an infra index, a compliance list). No frontmatter required. The directory is user-created and optional.

**The standing rules bind regardless of which index is loaded.** A custom list is still a lens, not a license - it widens noticing, it does not lower the finding bar or license unasked code. Invoking `care` twice (built-in + custom) simply stacks both lenses in context; that's fine and occasionally exactly what you want.

## The index

CORRECTNESS & DATA
BAD INPUTS - malformed, missing, hostile, duplicate, too big?
NULL / EMPTY / ZERO - first run, empty list, absent field, zero as a legit value?
BOUNDARIES - off-by-one, inclusive vs exclusive, pagination edges, max sizes?
ENCODING - unicode names, emoji, bytes vs chars, normalization?
TIME - timezones, DST, clock skew, expiry, "tomorrow" at 23:59?
MONEY / PRECISION - floats where currency lives, rounding drift, negative amounts?
INVARIANTS - what must always be true - enforced, or hoped?
ONE SOURCE OF TRUTH - duplicated state that can disagree - which one wins?

RESILIENCE
INSTANCE DIES - what in-flight state is lost, what's half-written?
DEPS FAIL - timeout, partial success, poison message, slow-not-down?
TIMEOUTS EVERYWHERE - any network call without one?
RETRIES - idempotent? backoff + jitter, or a retry storm?
ATOMICITY - two writes, one fails - what state remains?
FAIL OPEN OR CLOSED - what does an error in the check itself allow through?
KILL SWITCH / ROLLBACK - can you turn it off? can you undo the deploy?

CONCURRENCY & SCALE
RACES - two at once, out of order, delivered twice?
UNBOUNDED GROWTH - what accumulates with no cap - queue, cache, table, log?
HORIZONTAL SCALE - what breaks at 2 instances - local state, locks, cron x N?
HOT PATH - N+1, chatty loop, payload size at real volume?
CACHING - staleness, invalidation, stampede on expiry?
BACKPRESSURE - flooded downstream, throttled upstream - then what?
ORDERING - do you assume events arrive in order? they won't.

SECURITY & TENANCY
AUTHZ - whose data is this? checked on write as well as read?
TENANCY - can org A's id reach org B's rows?
INJECTION - untrusted strings reaching shell, SQL, HTML, prompt?
SECRETS - keys in code, in logs, in error messages?
LEAST PRIVILEGE - does this need the access it has?
PII IN LOGS - what leaks when you debug in prod?

DESIGN & CHANGE
SEAMS - swappable behind an interface, or welded in?
HONEST NAMES - does the name say what it does - or lie?
COUPLING - dependency direction right? low-level importing high-level?
DEAD WEIGHT - kept for symmetry, "just in case", never branched on?
MIGRATION - old data, old clients, both versions live mid-deploy?
API EVOLUTION - additive or breaking? versioned?
LOCALITY - can a stranger read this function alone and get it?

OPERABILITY & UX
OBSERVABILITY - will you KNOW when this breaks, and what it was doing?
ERROR MESSAGES - actionable for the human who hits them?
CONFIG / ENVIRONMENTS - works on dev, dies in prod? hardcoded values?
SAFE DEFAULTS - absence of config fails closed? sane out of the box?
UX STATES - loading, empty, error, success - do all four exist?
ACCESSIBILITY - keyboard, contrast, screen reader on anything user-facing?

== APPENDED THE "WHAT YOU CARE ABOUT" INDEX ==

## Composition

- **Pairs with `slice-review`**: the index widens the candidate search; the repro bar and mutation probe hold the finding contract. Neither is safe alone - a lens without the bar manufactures findings, the bar without the lens misses categories.
- **Pairs with `skeleton`/`slice`**: anchors noticed while implementing feed the Deferred list and the ledger, never the diff (rule 2).
- **Sits under `.claude/self-check.md`**: this is the generic tier - static priors for day one; self-check is the earned, per-repo tier that outranks it and keeps growing via the review ratchet.
- **Not a persona**: use `bdx:persona` when you want an opinionated voice; use this when you want the noticing without the personality. They stack fine.
- **Custom indexes** live at `$AGENT_HOME/care/<name>.md` (same convention as `$AGENT_HOME/personas/`): per-domain attention lists - frontend, data-pipeline, infra, compliance - swapped in via the argument. The built-in index stays the general-software default; a custom index is for when the domain's failure modes aren't general.

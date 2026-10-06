# Idle math reference (Corehold + reusable)

Formulas and pacing heuristics for incremental/idle economies. Sources (ideas only, no code copied): Kongregate "The Math of Idle Games" (Pecorella), see `third_party/README.md`. Use alongside `tools/balance.mjs` and the `playtest-audit` bot — numbers here are starting points, the bot's metrics are the truth.

## 1. Exponential cost
`cost(n) = base * r^n` for the n-th purchase (n from 0). Typical `r`: 1.07–1.15 for frequently bought upgrades, 1.5–3 for rare/strong ones. Lower `r` = longer engagement per upgrade line; production must grow polynomially (linear per level) so costs eventually outrun it — that wall is what makes prestige attractive.

## 2. Bulk buy
Cost of buying k more when you own n:
`sum = base * r^n * (r^k - 1) / (r - 1)`
Max affordable with cash c:
`k = floor( log( c*(r-1) / (base * r^n) + 1 ) / log(r) )`
Compute in floats, then verify with an integer loop for the last step to avoid off-by-one at boundaries.

## 3. Production and multipliers
`income = sum_i (rate_i * owned_i) * product_j(mult_j)`. Keep additive bonuses (+x%) inside one bucket and multiply buckets (labs × cards × perks × tier) so each system feels meaningful without one dominating. Milestone multipliers (e.g. ×2 at levels 25/50/100) create visible goals. Time-to-next-purchase = `cost / income` — the core pacing number.

## 4. Prestige
Prestige currency `p = floor( k * sqrt(lifetime_earnings / scale) )` (or a cube root for slower curves). Sub-linear growth means each reset needs ~4× more earnings to double reward, which naturally spaces resets. Give each prestige point a multiplicative boost (e.g. +2% income per point) so the next run reaches the previous wall in ~1/3–1/2 the time.

## 5. Offline earnings
`offline = income_at_logout * min(elapsed, cap) * efficiency` with efficiency 0.25–1.0 and a cap (e.g. 2–24 h, upgradable). Never simulate combat offline; use a stored rate. Clamp negative/forward-skewed clocks.

## 6. Pacing heuristics
- First purchase within ~10 s; something new to do every 30–60 s in the first 10 min.
- Time-to-next-upgrade should grow roughly log-linearly; flag any step > 3× its predecessor (death-spiral / wall).
- First prestige ~30–60 min of play; it should feel like a speed-up within the first 2 min of the new run.
- Keep at least two upgrade lines "close" (≤ 2× current wait) so the player always has a choice.
- Large numbers: format with suffixes (K, M, B, T, aa…) and keep ≤ 4 significant digits; use floats beyond 2^53.

## 7. Corehold mapping
Cash (per-run, exponential building upgrades) → coins (meta, workshop/labs) → gems (rare, cards/perks). Tiers are the prestige axis; labs are timers (real-time sinks); offline uses §5. Tune against `selftest`/`playtest` invariants, never by editing tests.

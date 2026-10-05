# TODO status (meta-economy pass)

1. **Early Core-level stall: done.** `Cores.level_cost` charges coins only below L15 (`pc_core_cc_from`, default 15). From L15 each level costs floor(L/5) Core Cores, so later levels stay gated. Selftest: the "CORE level cost" check and the coin-only L2->L15 / L15->L16 checks (updated on purpose; they used to assert Core Cores from L5).
2. **Factory Outpost economy: partly done.**
   - Storage away cap is now 6 h + 0.015 h per slot (was 4 h + 0.02 h). A bare start gives 6 h and 4 chests + vault give about 13.7 h, so both sit inside the AC-27 band of [6, 16] h. The gate band is unchanged.
   - The bot's `FACTORY_PLAN` now buys land chunk 14 and researches Electronics and Data. It builds an iron/copper -> wire -> circuit -> data-card chain (with crystal -> shard), powered by 12 windmills, and one belt carries the products to the Relay's bottom face. A sim gives about 0.25 data/s.
   - Fixed a plan bug: the Vault sat in a chest step before Vaults research, which stalled every later plan step. It now comes after `storage2`.
   - Selftest: META bot-plan, storage-band and Lancer checks.
   - **Open:** there is no key-blank chain. Alloy needs the start-chunk scrap, which is already belted to the Relay, and there was no room to fit it in time. The `rd_outpost_share` coin share is unchanged: the factory's coin rate is the same as before, and the data goes to research.
3. **Lancer: data trim.** The 2-piece bonus is now +2% Core damage (was +5%). The 4-piece pierce is kept. Whether this is enough has not been measured yet; see the playtest note.
4. **Tier pacing: done.** `tier_unlock_base` 20 -> 10, so T2 unlocks at w30, T3 at w40 and T4 at w50. The tier selftests were moved to the new waves on purpose.

**Playtest:** one run was started after the gates passed. It was still running when the 90-minute limit was reached (its full multi-seed campaign takes more than 60 minutes), so no gate results are recorded. Next step: run playtest.gd once and check rd_outpost_share, rd_ac27_storage_fill, set4 Lancer, t2_by_day5 and tier3_by_day30.

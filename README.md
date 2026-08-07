# Goblin

A TBC Classic (`2.5.6` / interface `20506`) account net-worth addon using TradeSkillMaster's public pricing API.

## Install and use

1. Copy the `Goblin` directory into `World of Warcraft/_classic_/Interface/AddOns/` beside `TradeSkillMaster` and `TradeSkillMaster_AppHelper`.
2. Log into each character whose inventory should be included.
3. Open that character's bank, mailbox, auction house, and each guild bank tab to refresh those snapshots.
4. Type `/goblin` (`/sl` and `/ledger` are aliases).
5. Enter any valid TSM price source or expression and press Enter. Examples: `dbmarket`, `dbregionmarketavg`, `min(dbmarket, dbregionmarketavg)`, or one of your custom sources.

The scrollable **Sources** panel independently controls global storage categories, soulbound items, each character and that character's individual locations, each guild bank and its scanned tabs, character gold, and guild-bank gold. Equipped and soulbound items default to excluded globally.

## Snapshot behavior

WoW only exposes bank, mail, auction, and guild-bank contents while those interfaces are available. Goblin therefore saves the latest observed contents. A future UI pass should display per-source scan timestamps and add explicit stale-data warnings.

# Goblin

A TBC Classic (`2.5.6` / interface `20506`) account net-worth addon using TradeSkillMaster's public pricing API.

## Install and use

1. Copy the `Goblin` directory into `World of Warcraft/_classic_/Interface/AddOns/` beside `TradeSkillMaster` and `TradeSkillMaster_AppHelper`.
2. Log into each character whose inventory should be included.
3. Open that character's bank, mailbox, auction house, and each guild bank tab to refresh those snapshots.
4. Type `/goblin` (`/sl` and `/ledger` are aliases).
5. Enter any valid TSM price source or expression and press Enter. Examples: `dbmarket`, `dbregionmarketavg`, `min(dbmarket, dbregionmarketavg)`, or one of your custom sources.

The scrollable **Sources** panel independently controls global storage categories, soulbound items, each character and that character's individual locations, each guild bank and its scanned tabs, character gold, and guild-bank gold. Equipped and soulbound items default to excluded globally.

## Tabs

- **Summary** — net-worth rollups by character and location.
- **Inventory** — the per-item ledger with search, sorting, and per-location columns.
- **Mail** — every tracked mail across every alt, with dual expiry clocks (see below).
- **Coverage** — per-source scan freshness, unpriced-item counts, and warnings.

## Mail tracking

Using the mailbox as bulk storage is normal practice and the game gives you no account-wide view of it. The Mail tab builds one.

Every time a character opens its mailbox, Goblin snapshots each message: sender, subject, attachments, attached gold, COD, and the game's own `daysLeft` value. Because that countdown runs in real time whether or not you are logged in, the tab projects it forward from the snapshot timestamp rather than assuming it is current.

Two deadlines are tracked, because they are not the same deadline:

- **Returns in** — player-to-player mail bounces back to the sender after 30 days. The items are not gone; they have moved to a different inbox and restarted their clock there.
- **Deleted in** — 30 days after that, the mail is destroyed. Auction-house mail and mail that has already bounced once have no return leg, so their single countdown runs straight to deletion.

Each row draws both as a two-segment bar: the bright segment is time before the parcel moves, the dim segment is the grace period after. Rows are colored red under a day, orange under three, gold under seven. The tab header carries a badge with the count of mail inside the warning window, and the minimap tooltip shows the same.

Rows sourced from a mailbox you haven't visited recently are flagged as projected — open that mailbox to confirm. Shipments that Goblin's `SendMail` hook recorded but no inbox scan has yet confirmed appear in a separate **In transit** group and are marked unconfirmed, since they are inferred rather than observed.

Filters: urgent only, hide AH mail, hide empty mail (on by default). Hover any row for the full manifest with per-item values.

## Reading the numbers

- **Items held** counts individual items, so 200 Netherweave Cloth is 200. The subtitle counts distinct item types.
- **Per character** covers bags, bank, equipped, mail, auctions and gold. Guild-bank contents are deliberately *not* split across characters — a guild bank belongs to the guild, and attributing it to members would double-count the moment two alts share one. It appears under Value by location instead.
- **Value by location** only draws locations that hold something. Anything switched off in Sources, or genuinely empty, is named underneath rather than drawn as a zero-width slice.
- **Coverage pills** read "11 items · 1 no price · 16h ago". The item count is distinct item types in that bucket, not stack or slot count. The gold pill shows an amount.
- **Count soulbound items** (Sources panel) applies everywhere, not just to equipped gear — soulbound items in bags, bank, mail or a guild bank are excluded too. Off by default, so the total reflects what you could actually sell. The Sources footer reports how much is being held back.

## Trend accuracy

Net-worth snapshots record a fingerprint of the source selection and price source that produced them. The trend widgets only ever compare two totals taken under the same configuration; switching a guild bank off used to read as an overnight collapse. When no comparable baseline exists, the widget says "sources changed — rebuilding baseline" instead of reporting a bogus swing.

Snapshots are also suppressed while the Sources panel is open (you are mid-edit) and before TSM can price anything (the addon can load ahead of its dependency). If a trend line is already poisoned, `/goblin history reset` clears it.

## Snapshot behavior

WoW only exposes bank, mail, auction, and guild-bank contents while those interfaces are available. Goblin therefore saves the latest observed contents. The Coverage tab and the Mail tab both surface per-source scan age so you can tell stale data from current data.

## Commands

```
/goblin                  toggle the ledger
/goblin net              print current net worth
/goblin mail             every tracked mail, where it sits, and its expiry clocks
/goblin mail transit     only shipments hooked at send but not yet confirmed
/goblin stale            list unscanned/stale sources
/goblin trace <name>     show every source Goblin has for an item
/goblin coverage [all]   per-character/guild source scan status and warnings
/goblin diff [threshold] per-item Goblin vs TSM NumInventory diff
/goblin history reset    clear the net-worth trend line and start fresh
/goblin rescan           wipe current guild bank cache and re-query
```

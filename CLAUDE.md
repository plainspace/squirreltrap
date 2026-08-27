# Squirrel Trap — standing engineering rules

## Data safety: duplication over deletion, always

At all times, under all circumstances, avoiding data loss outranks every
other concern in this codebase. Squirrel Trap must never be the reason a
user loses a to-do.

**The rule:** whenever a sync or persistence code path has to choose
between two failure modes — silently discarding/overwriting local data,
versus leaving something duplicated, stale, or in a recoverable
not-quite-clean state — always choose the latter. Deduplicating or
cleaning up an extra copy later is trivial. Recreating a to-do someone
already lost is not possible at all.

Concretely, this means:

- **A parse/decode failure on `entries.json` (or any persisted store) must
  never be treated as "empty."** `(try? decode(...)) ?? []` silently
  wipes everything the moment the next `save()` fires. On a decode
  failure, preserve the original file (copy it aside) before ever letting
  the in-memory state overwrite it. See `IntentStore.load()`.
- **A sync engine must not delete local data on an inferred or ambiguous
  remote signal.** Only delete when the remote side has explicitly and
  unambiguously reported "this was deleted" (e.g. CloudKit's own
  deletion-token mechanism). Never infer a deletion from "I didn't see it
  in this fetch" — a stale, partial, or failed fetch looks identical to a
  real deletion from that vantage point. `ReminderSyncEngine` already
  learned this the hard way (see its `pull()` doc comment) — a stale
  fetch once wiped local entries because a linked Reminder briefly looked
  "gone." It now never deletes on either side for exactly this reason;
  don't reintroduce that class of bug elsewhere.
- **Two writers racing on the same local file is a data-loss bug, not
  just a debugging nuisance.** `SquirrelTrapApp` now refuses to launch a
  second instance for this reason (`applicationDidFinishLaunching`'s
  single-instance guard) — a silent last-writer-wins overwrite on
  `entries.json` is a real, demonstrated scenario, not a hypothetical.
- **A sync error should fail loudly (or at least visibly/recoverably),
  never silently as "nothing happened."** `CloudSyncEngine.lastSyncError`
  exists so a failed sync is distinguishable from a successful one in the
  UI, instead of both looking identical to the user.
- **Recovering from an un-syncable state (e.g. an expired CloudKit change
  token) should degrade to "do more work" (a full re-fetch), never to
  "assume local is right and push over it" or "assume remote is right and
  delete locally."**

**What this does *not* mean:** this is not a license to add exhaustive
logging, redundant backups of every field on every keystroke, or
elaborate conflict-resolution UI for routine last-write-wins edit
conflicts (e.g. the same to-do edited on two Macs within the same sync
window — CloudSyncEngine/ReminderSyncEngine's existing "most recent
`lastModifiedAt` wins" resolution is an accepted, reasonable tradeoff,
not a bug to re-litigate). Apply judgment: the bar is "don't destroy a
user's to-do because of an ambiguous or erroneous signal," not "make
every write immortal."

When touching `IntentStore`, `CloudSyncEngine`, or `ReminderSyncEngine`,
re-read this section and ask: *could this path ever turn "I'm not sure"
into "delete it anyway"?* If so, it needs to fail toward keeping data,
not discarding it.

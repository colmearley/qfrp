# qfrp

**Functional Reactive Programming in q/KDB+** — by Thalesians Ltd.

## What is FRP?

Functional Reactive Programming models time-varying values as two primitives:

- **Streams** — discrete sequences of events (a value fires at a point in time)
- **Cells** — continuously-held values that change in response to stream events

You compose streams and cells using pure functions (`map`, `filter`, `merge`, `snapshot`) rather than wiring callbacks by hand. The runtime guarantees consistent, glitch-free propagation.

## Architecture

### Rank-based topological ordering

Every stream and cell carries an integer **rank**:

- Source streams have rank 0
- Every derived stream/cell has `rank = max(source ranks) + 1`

Within a transaction, events are processed in ascending rank order. This guarantees a derived node never fires before its inputs in the same transaction — no glitches.

### ID/dictionary state model

Streams and cells are q dictionaries with an `id` key. Global dictionaries in `.frp` hold all metadata:

| Dict | Key type | Value |
|------|----------|-------|
| `sranks` | stream ID | rank (int) |
| `subs` | stream ID | list of subscriber functions |
| `cvals` | cell ID | current value |
| `cmeta` | cell ID | `(updates stream ID; rank)` |

## Transaction Model

| Component | Role |
|-----------|------|
| `txq` | List of `(rank; seq; thunk)` triples queued in the current transaction |
| `send` | Enqueues a thunk at the stream's rank |
| `flush` | Sorts queue by `(rank, seq)`, executes each thunk; recurses if new events were enqueued mid-propagation |
| `trans` | Opens/closes a transaction; re-entrant guard (`tx` flag) means nested calls are no-ops |

## API Reference

### Streams

| Function | Description |
|----------|-------------|
| `newStream[rank]` | Create a new source stream at the given rank |
| `send[s; x]` | Fire event `x` on stream `s` (opens a transaction if needed) |
| `listen[s; fn]` | Attach listener `fn` to stream `s`; returns an unsubscribe token |
| `unlisten[tok]` | Remove a previously attached listener |

### Combinators

| Function | Description |
|----------|-------------|
| `map[s; g]` | New stream that applies `g` to every event from `s` |
| `filter[s; p]` | New stream that forwards only events where predicate `p` is true |
| `merge[a; b]` | New stream that emits events from either `a` or `b` |
| `snapshot[s; c; f]` | When `s` fires, sample cell `c` and emit `f[event; cellVal]` |

### Cells

| Function | Description |
|----------|-------------|
| `hold[init; s]` | Cell that stores the latest value from stream `s`; starts at `init` |
| `accum[init; s; step]` | State-machine cell; `step[currentState; event]` → new state |
| `sample[c]` | Read a cell's current value (safe to call inside listeners) |
| `updates[c]` | Return the internal updates stream of a cell |

## Quick Example

```q
s:.frp.newStream 0;           / source stream, rank 0
s2:.frp.map[s; {x*2}];        / derived stream, rank 1
c:.frp.hold[10; s2];           / cell that holds latest value of s2, rank 2
snap:.frp.snapshot[s2; c; {x,y}];  / snapshot c when s2 fires, rank 3
tok:.frp.listen[snap; {show x}];

.frp.send[s; 1];  / prints (2;2)
.frp.send[s; 2];  / prints (4;4)
```

Within each transaction, events propagate in rank order: `s` (0) → `s2` (1) → `c` (2) → `snap` (3). The cell `c` is updated before `snap` samples it, so the snapshot sees the new value — never the stale one.

## How to Run

```q
q frp.q
```

The smoke test at the bottom of `frp.q` prints `(2;2)` then `(4;4)`.

-1 "  ______ _____  _____ ";
-1 " |  ____|  __ \\|  __ \\";
-1 " | |__  | |__) | |__) |";
-1 " |  __| |  _  /|  ___/ ";
-1 " | |    | | \\ \\| |     ";
-1 " |_|    |_|  \\_\\_|     ";
-1 " Functional Reactive Programming in q";
-1 "--------------------------------------";
-1 "Copyright (c) Thalesians Ltd, 2026";
-1 "--------------------------------------";

\d .frp

/ ---------- global state ----------
idCounter:0i;
newId:{ .frp.idCounter+:1i; .frp.idCounter }

/ stream metadata: sid -> rank (int)
sranks:()!();
/ stream subscribers: sid -> list of fns (each: {x} -> ())
subs:()!();

/ cell state: cid -> value
cvals:()!();
/ cell metadata: cid -> (updatesSid; rank)
cmeta:()!();

/ transaction state
tx:0b;
seq:0i;
txq:();  / list of (rank;seq;thunk)

/ ---------- tx helpers ----------
enq:{[rnk; thunk]
  .frp.seq+:1i;
  .frp.txq,: enlist (rnk; .frp.seq; thunk);
  :: }

flush:{
  if[0=count .frp.txq; :()];
  ord: iasc (.frp.txq[;0], .frp.txq[;1]);
  todo: .frp.txq ord;
  .frp.txq:();
  { (x 2)[] } each todo;     / <-- CALL the thunk
  if[count .frp.txq; .frp.flush[]];
  :: }

trans:{[f]
  if[.frp.tx; :f[]];
  .frp.tx:1b;
  r: f[];
  .frp.flush[];
  .frp.tx:0b;
  r }

/ ---------- Stream core ----------
newStream:{[rnk]
  sid:.frp.newId[];
  .frp.sranks[sid]:rnk;
  .frp.subs[sid]:();
  `id`rank!(sid; rnk) }

/ stream rank (do not call this 'rank')
srank:{[s] .frp.sranks[s`id] }

listen:{[s; fn]
  sid:s`id;
  .frp.subs[sid],: enlist fn;
  (sid; (count .frp.subs[sid]) - 1) }

noop1:{[x] :: }

unlisten:{[tok]
  sid: tok 0;
  i:   tok 1;
  if[not sid in key .frp.subs; :()];
  fs:.frp.subs[sid];
  if[i<0 or i>=count fs; :()];
  fs[i]: .frp.noop1;
  .frp.subs[sid]: fs;
  :: }

send:{[s; x]
  sid:s`id;
  rnk:.frp.sranks[sid];

  th:{[sid; x]
    fs:.frp.subs[sid];
    ({[x;f] f x}[x;] each fs);   / bind x, then call each f with x
    :: }[sid; x];

  if[.frp.tx; .frp.enq[rnk; th]; :()];

  .frp.trans[
    { [rnk; th] .frp.enq[rnk; th]; :: }[rnk; th]
  ];

  :: }

/ ---------- Stream combinators ----------
map:{[s; g]
  out:.frp.newStream[1 + .frp.srank s];
  .frp.listen[s; { [out;g;x] .frp.send[out; g x] }[out;g]];
  out }

filter:{[s; p]
  out:.frp.newStream[1 + .frp.srank s];
  .frp.listen[s; { [out;p;x] if[p x; .frp.send[out; x]] }[out;p]];
  out }

/ merge emits events from either; deterministic by tx ordering + subscriber order
merge:{[a; b]
  out:.frp.newStream[1 + max(.frp.srank a; .frp.srank b)];
  .frp.listen[a; { [out;x] .frp.send[out; x] }[out]];
  .frp.listen[b; { [out;x] .frp.send[out; x] }[out]];
  out }

/ snapshot: when stream fires, sample cell and apply f(event, cellVal)
snapshot:{[s; c; f]
  out:.frp.newStream[1 + max(.frp.srank s; c`rank)];
  .frp.listen[s; { [out;c;f;x] .frp.send[out; f[x; .frp.sample c] ] }[out;c;f]];
  out }

/ ---------- Cell core ----------
/ Cell is: (`id`rank`updates)! (cid; crank; upsStreamObj)
hold:{[init; s]
  cid:.frp.newId[];
  crank:1 + .frp.srank s;

  ups:.frp.newStream[crank];
  .frp.cvals[cid]:init;
  .frp.cmeta[cid]:(ups`id; crank);

  / commit state first at cell rank
  .frp.listen[ups; { [cid;x] .frp.cvals[cid]: x; :: }[cid] ];

  / forward source stream to updates
  .frp.listen[s; { [ups;x] .frp.send[ups; x] }[ups]];

  `id`rank`updates!(cid; crank; ups) }

sample:{[c] .frp.cvals[c`id] }

updates:{[c]
  sid:c`updates`id;
  `id`rank!(sid; .frp.sranks[sid]) }

/ accum: state machine cell driven by stream
/ step: {[state; x] -> newState}
accum:{[init; s; step]
  cid:.frp.newId[];
  crank:1 + .frp.srank s;
  ups:.frp.newStream[crank];

  .frp.cvals[cid]:init;
  .frp.cmeta[cid]:(ups`id; crank);

  / commit state first
  .frp.listen[ups; { [cid;x] .frp.cvals[cid]: x; :: }[cid] ];

  / compute next state from current state
  .frp.listen[s; { [cid;ups;step;x]
      st:.frp.cvals[cid];
      .frp.send[ups; step[st; x] ];
    }[cid;ups;step] ];

  `id`rank`updates!(cid; crank; ups) }

\d .

/ -------------------------
/ quick smoke test
/ -------------------------
s:.frp.newStream 0;
s2:.frp.map[s; {x*2}];
c:.frp.hold[10; s2];
snap:.frp.snapshot[s2; c; {x,y}];
tok:.frp.listen[snap; {show x}];

.frp.send[s; 1];  / prints (2;2) because hold updates then snapshot samples
.frp.send[s; 2];  / prints (4;4)

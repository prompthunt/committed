// Synthesizes the launch film's score to assets/score.wav. No dependencies, fully deterministic.
// Every hit is placed from timing.js, the same grid the picture uses.
//   node scripts/score.mjs
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

globalThis.window = {};
await import("../timing.js");
const T = window.TIMING;
const { at, cue, BEAT } = T;

const SR = 48000;
const N = Math.round(T.DURATION * SR);
const TAU = Math.PI * 2;
const S = (t) => Math.round(t * SR);

// ---------- utilities ----------
function rngFrom(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
let seedCounter = 1;
const noiseGen = () => {
  const r = rngFrom(0x9e3779b9 ^ seedCounter++ * 2654435761);
  return () => r() * 2 - 1;
};

const bus = () => [new Float32Array(N), new Float32Array(N)];
const drums = bus();
const music = bus(); // sidechained
const fx = bus();
const send = bus(); // reverb send

function put(b, i, v, pan = 0) {
  if (i < 0 || i >= N) return;
  const a = ((pan + 1) * Math.PI) / 4;
  b[0][i] += v * Math.cos(a) * Math.SQRT2;
  b[1][i] += v * Math.sin(a) * Math.SQRT2;
}

class Biquad {
  constructor(type, f, q = 0.707) {
    this.type = type;
    this.x1 = this.x2 = this.y1 = this.y2 = 0;
    this.set(f, q);
  }
  set(f, q = this.q) {
    this.q = q;
    f = Math.min(Math.max(f, 10), SR * 0.45);
    const w = (TAU * f) / SR;
    const c = Math.cos(w);
    const s = Math.sin(w);
    const al = s / (2 * q);
    let b0, b1, b2;
    if (this.type === "lp") [b0, b1, b2] = [(1 - c) / 2, 1 - c, (1 - c) / 2];
    else if (this.type === "hp") [b0, b1, b2] = [(1 + c) / 2, -(1 + c), (1 + c) / 2];
    else [b0, b1, b2] = [al, 0, -al];
    const a0 = 1 + al;
    this.b0 = b0 / a0;
    this.b1 = b1 / a0;
    this.b2 = b2 / a0;
    this.a1 = (-2 * c) / a0;
    this.a2 = (1 - al) / a0;
    return this;
  }
  run(x) {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1;
    this.x1 = x;
    this.y2 = this.y1;
    this.y1 = y;
    return y;
  }
}

// polyBLEP sawtooth
function blep(t, dt) {
  if (t < dt) {
    t /= dt;
    return t + t - t * t - 1;
  }
  if (t > 1 - dt) {
    t = (t - 1) / dt;
    return t * t + t + t + 1;
  }
  return 0;
}

const NOTE = (name) => {
  const m = /^([A-G])(#?)(-?\d)$/.exec(name);
  const semis = { C: -9, D: -7, E: -5, F: -4, G: -2, A: 0, B: 2 }[m[1]] + (m[2] ? 1 : 0);
  return 440 * Math.pow(2, (semis + (Number(m[3]) - 4) * 12) / 12);
};

// ---------- instruments ----------
function kick(t0, g = 1) {
  const n = noiseGen();
  const i0 = S(t0);
  let ph = 0;
  for (let k = 0; k < S(0.55); k++) {
    const tt = k / SR;
    const f = 44 + 130 * Math.exp(-tt * 32) + 40 * Math.exp(-tt * 260);
    ph += (TAU * f) / SR;
    const amp = Math.min(1, tt / 0.0015) * Math.exp(-tt * 6.2);
    const click = n() * Math.exp(-tt * 900) * 0.4;
    put(drums, i0 + k, Math.tanh((Math.sin(ph) * amp + click) * 1.7) * 0.8 * g);
  }
}

function clap(t0, g = 1) {
  const nl = noiseGen();
  const nr = noiseGen();
  const fl = new Biquad("bp", 1350, 0.9);
  const fr = new Biquad("bp", 1500, 0.9);
  const i0 = S(t0);
  for (let k = 0; k < S(0.32); k++) {
    const tt = k / SR;
    let env = 0;
    for (const o of [0, 0.0105, 0.021]) if (tt >= o) env = Math.max(env, Math.exp(-(tt - o) * 190));
    if (tt >= 0.028) env = Math.max(env, 0.75 * Math.exp(-(tt - 0.028) * 15));
    const l = fl.run(nl()) * env * g * 0.9;
    const r = fr.run(nr()) * env * g * 0.9;
    if (i0 + k < N) {
      drums[0][i0 + k] += l;
      drums[1][i0 + k] += r;
      send[0][i0 + k] += l * 0.35;
      send[1][i0 + k] += r * 0.35;
    }
  }
}

function snare(t0, g = 1) {
  const n = noiseGen();
  const f = new Biquad("bp", 2100, 0.8);
  const i0 = S(t0);
  let ph = 0;
  for (let k = 0; k < S(0.2); k++) {
    const tt = k / SR;
    ph += (TAU * (185 + 60 * Math.exp(-tt * 40))) / SR;
    const v = (f.run(n()) * Math.exp(-tt * 22) * 0.9 + Math.sin(ph) * Math.exp(-tt * 30) * 0.5) * g;
    put(drums, i0 + k, v, 0.05);
    if (i0 + k < N) {
      send[0][i0 + k] += v * 0.2;
      send[1][i0 + k] += v * 0.2;
    }
  }
}

function hat(t0, g = 1, open = false, pan = 0.25) {
  const n = noiseGen();
  const hp = new Biquad("hp", 7600, 0.7);
  const bp = new Biquad("bp", 10500, 1.2);
  const i0 = S(t0);
  const len = open ? 0.32 : 0.07;
  const dec = open ? 13 : 75;
  for (let k = 0; k < S(len); k++) {
    const tt = k / SR;
    const x = n();
    put(drums, i0 + k, (hp.run(x) * 0.6 + bp.run(x) * 0.5) * Math.exp(-tt * dec) * g, pan);
  }
}

// FM bell; rev = reverb send amount
function bell(t0, f, g = 0.2, pan = 0, decay = 3, rev = 0.45, ratio = 2) {
  const i0 = S(t0);
  const len = Math.min(S(Math.max(0.4, 5 / decay)), N - i0);
  for (let k = 0; k < len; k++) {
    const tt = k / SR;
    const idx = 2.2 * Math.exp(-tt * 7);
    const env = Math.min(1, tt / 0.002) * Math.exp(-tt * decay);
    const v =
      (Math.sin(TAU * f * tt + idx * Math.sin(TAU * f * ratio * tt)) +
        0.18 * Math.sin(TAU * f * 3.01 * tt) * Math.exp(-tt * decay * 2)) *
      env *
      g;
    put(fx, i0 + k, v, pan);
    if (i0 + k < N) {
      send[0][i0 + k] += v * rev;
      send[1][i0 + k] += v * rev;
    }
  }
}

// short UI blip, optional pitch glide
function blip(t0, f0, f1 = f0, g = 0.12, len = 0.06, pan = 0) {
  const i0 = S(t0);
  let ph = 0;
  for (let k = 0; k < S(len); k++) {
    const tt = k / SR;
    const p = tt / len;
    ph += (TAU * (f0 + (f1 - f0) * p)) / SR;
    const env = Math.min(1, tt / 0.002) * Math.pow(1 - p, 2);
    const v = (Math.sin(ph) + 0.25 * Math.sin(ph * 2)) * env * g;
    put(fx, i0 + k, v, pan);
    if (i0 + k < N) {
      send[0][i0 + k] += v * 0.25;
      send[1][i0 + k] += v * 0.25;
    }
  }
}

function tick(t0, g = 0.06, f = 3800, pan = 0) {
  const n = noiseGen();
  const bp = new Biquad("bp", f, 3);
  const i0 = S(t0);
  for (let k = 0; k < S(0.018); k++) put(fx, i0 + k, bp.run(n()) * Math.exp(-(k / SR) * 320) * g * 2.2, pan);
}

// filtered-noise whoosh: centre frequency glides f0→f1, bell-shaped amplitude, pan glides
function whoosh(t0, dur, g = 0.25, f0 = 300, f1 = 3000, pan0 = 0, pan1 = 0, shape = 0.5) {
  const nl = noiseGen();
  const fl = new Biquad("bp", f0, 1.1);
  const fr = new Biquad("bp", f0, 1.1);
  const i0 = S(t0);
  const len = S(dur);
  for (let k = 0; k < len; k++) {
    const p = k / len;
    if (k % 32 === 0) {
      const f = f0 * Math.pow(f1 / f0, p);
      fl.set(f, 1.1);
      fr.set(f * 1.04, 1.1);
    }
    // asymmetric bell: peaks at `shape`
    const env = p < shape ? Math.pow(p / shape, 2) : Math.pow(1 - (p - shape) / (1 - shape), 1.6);
    const x = nl();
    const pan = pan0 + (pan1 - pan0) * p;
    const a = ((pan + 1) * Math.PI) / 4;
    if (i0 + k < N) {
      fx[0][i0 + k] += fl.run(x) * env * g * Math.cos(a) * 1.6;
      fx[1][i0 + k] += fr.run(x) * env * g * Math.sin(a) * 1.6;
    }
  }
}

// supersaw pad segment into the (sidechained) music bus
function pad(t0, t1, freqs, g = 0.05, cutoff = () => 2400, attack = 0.02, release = 0.12) {
  const voices = [];
  const det = [-0.19, -0.09, 0, 0.1, 0.2];
  freqs.forEach((f, ni) =>
    det.forEach((d, vi) => {
      const r = rngFrom(ni * 31 + vi * 7 + Math.round(f));
      voices.push({ f: f * Math.pow(2, d / 12), ph: r(), pan: ((vi / (det.length - 1)) * 2 - 1) * 0.7 });
    }),
  );
  const fl = new Biquad("lp", 2000, 0.8);
  const fr = new Biquad("lp", 2000, 0.8);
  const i0 = S(t0);
  const len = S(t1 - t0 + release);
  for (let k = 0; k < len && i0 + k < N; k++) {
    const t = t0 + k / SR;
    if (k % 32 === 0) {
      const c = cutoff(t);
      fl.set(c, 0.8);
      fr.set(c * 1.03, 0.8);
    }
    let l = 0;
    let r = 0;
    for (const v of voices) {
      const dt = v.f / SR;
      v.ph += dt;
      if (v.ph >= 1) v.ph -= 1;
      const s = 2 * v.ph - 1 - blep(v.ph, dt);
      const a = ((v.pan + 1) * Math.PI) / 4;
      l += s * Math.cos(a);
      r += s * Math.sin(a);
    }
    const tt = k / SR;
    const env = Math.min(1, tt / attack) * (t > t1 ? Math.max(0, 1 - (t - t1) / release) : 1);
    const norm = g / Math.sqrt(voices.length);
    music[0][i0 + k] += fl.run(l) * env * norm;
    music[1][i0 + k] += fr.run(r) * env * norm;
    send[0][i0 + k] += fl.y1 * env * norm * 0.15;
    send[1][i0 + k] += fr.y1 * env * norm * 0.15;
  }
}

function bass(t0, f, len = 0.2, g = 0.22) {
  const lp = new Biquad("lp", 2000, 1.3);
  const i0 = S(t0);
  let ph = 0;
  let sub = 0;
  for (let k = 0; k < S(len + 0.03); k++) {
    const tt = k / SR;
    if (k % 16 === 0) lp.set(240 + 2100 * Math.exp(-tt * 16), 1.3);
    const dt = (f * 2) / SR;
    ph += dt;
    if (ph >= 1) ph -= 1;
    sub += (TAU * f) / SR;
    const saw = 2 * ph - 1 - blep(ph, dt);
    const env = Math.min(1, tt / 0.004) * (tt < len ? Math.exp(-tt * 3) : Math.exp(-len * 3) * Math.max(0, 1 - (tt - len) / 0.03));
    put(music, i0 + k, (lp.run(saw) * 0.75 + Math.sin(sub) * 0.7) * env * g);
  }
}

// plucky arp note (into music bus so it pumps)
function pluck(t0, f, g = 0.06, pan = 0) {
  const lp = new Biquad("lp", 3000, 2);
  const i0 = S(t0);
  let ph = 0;
  for (let k = 0; k < S(0.22); k++) {
    const tt = k / SR;
    if (k % 16 === 0) lp.set(500 + 5000 * Math.exp(-tt * 28), 2);
    const dt = f / SR;
    ph += dt;
    if (ph >= 1) ph -= 1;
    const sq = (ph < 0.5 ? 1 : -1) * 0.6 + (2 * ph - 1) * 0.4;
    const v = lp.run(sq) * Math.exp(-tt * 14) * g;
    put(music, i0 + k, v, pan);
    if (i0 + k < N) {
      send[0][i0 + k] += v * 0.3;
      send[1][i0 + k] += v * 0.3;
    }
  }
}

function sub(t0, f0, f1, dur, g = 0.6) {
  const i0 = S(t0);
  let ph = 0;
  for (let k = 0; k < S(dur) && i0 + k < N; k++) {
    const tt = k / SR;
    ph += (TAU * (f1 + (f0 - f1) * Math.exp(-tt * 2.5))) / SR;
    put(fx, i0 + k, Math.sin(ph) * Math.min(1, tt / 0.004) * Math.exp(-tt * 2.1) * g);
  }
}

// ---------- arrangement ----------
const CH = {
  Am: ["A3", "C4", "E4", "A4"],
  F: ["A3", "C4", "F4", "A4"],
  C: ["G3", "C4", "E4", "G4"],
  G: ["G3", "B3", "D4", "G4"],
  Cfinal: ["C3", "G3", "C4", "E4", "G4", "C5"],
};
const ROOT = { Am: "A1", F: "F1", C: "C2", G: "G1" };
const hz = (names) => names.map(NOTE);

// chord per bar (bar 7 splits F → G)
const plan = [
  { t0: 0, t1: at(3), ch: "Am" },
  { t0: at(3), t1: at(4), ch: "F" },
  { t0: at(4), t1: at(5), ch: "C" },
  { t0: at(5), t1: at(6), ch: "G" },
  { t0: at(6), t1: at(7), ch: "Am" },
  { t0: at(7), t1: at(7, 3), ch: "F" },
  { t0: at(7, 3), t1: cue.gap, ch: "G" },
];
const chordAt = (t) => plan.find((p) => t >= p.t0 && t < p.t1)?.ch;

// pad filter: dark intro, opens on the drop, sweeps up through the build
const padCut = (t) => {
  if (t < cue.drop) return 500 + 900 * Math.pow(t / cue.drop, 2);
  if (t < cue.build) return 2600;
  return 2600 + 5000 * Math.pow((t - cue.build) / (cue.gap - cue.build), 2);
};
plan.forEach((p, i) => pad(p.t0, p.t1, hz(CH[p.ch]), i === 0 ? 0.06 : 0.075, padCut, i === 0 ? 0.6 : 0.015, i === plan.length - 1 ? 0.05 : 0.04));

// drums
for (const t of T.kicks) kick(t);
for (let bar = 2; bar <= 6; bar++) for (const b of [2, 4]) clap(at(bar, b), bar === 2 ? 0.8 : 1);
// bar 1: hats creep in from beat 3
for (let s = 0; s < 8; s++) hat(at(1, 3, s / 4), 0.04 + 0.05 * (s / 7));
for (let bar = 2; bar <= 7; bar++) {
  for (let s = 0; s < 16; s++) {
    const t = at(bar, 1, s / 4);
    if (bar === 7 && t >= cue.gap) continue;
    hat(t, [0.09, 0.04, 0.065, 0.04][s % 4], false, 0.3);
  }
  if (bar >= 3) for (let b = 1; b <= 4; b++) if (!(bar === 7 && b === 4)) hat(at(bar, b, 0.5), 0.1, true, -0.2);
}
// bar 7: snare roll — 8ths, 16ths, 32nds into the gap
{
  const hits = [
    ...[0, 0.5, 1, 1.5].map((b) => at(7, 1, b)),
    ...[0, 0.25].map((b) => at(7, 3, b)),
    ...[0.5, 0.625, 0.75, 0.875].map((b) => at(7, 3, b)),
  ];
  hits.forEach((t, i) => snare(t, 0.25 + 0.65 * (i / (hits.length - 1))));
}

// bass on the offbeats, bars 2–7
for (let bar = 2; bar <= 7; bar++)
  for (let b = 1; b <= 4; b++) {
    const t = at(bar, b, 0.5);
    if (t >= cue.gap) continue;
    bass(t, NOTE(ROOT[chordAt(t)]), 0.17);
  }

// arp: bars 3–6, 16ths over chord tones an octave up
const ARP = [0, 2, 1, 3, 2, 1, 3, 0];
for (let bar = 3; bar <= 6; bar++)
  for (let s = 0; s < 16; s++) {
    const t = at(bar, 1, s / 4);
    const tones = hz(CH[chordAt(t)]).map((f) => f * 2);
    pluck(t, tones[ARP[s % 8] % tones.length], s % 4 === 0 ? 0.05 : 0.035, s % 2 ? 0.45 : -0.45);
  }

// ---------- sound design, locked to picture cues ----------
// the first square lands
bell(cue.seed, NOTE("A5"), 0.24, 0.35, 2.2, 0.6);
blip(cue.seed, 220, 660, 0.12, 0.05, 0.35);
// the year ripples in from the right edge (today) toward the left
{
  const scale = ["A5", "C6", "D6", "E6", "G6", "A6", "C7", "D7", "E7", "G7"].map(NOTE);
  const n = 18;
  for (let i = 0; i < n; i++) {
    const p = i / (n - 1);
    const t = cue.ripple + 0.48 * Math.pow(p, 0.85);
    bell(t, scale[Math.min(scale.length - 1, Math.floor(p * scale.length))], 0.06 * (1 - p * 0.4), 0.6 - 1.2 * p, 4, 0.7);
  }
  whoosh(cue.ripple - 0.08, 0.62, 0.12, 200, 2500, 0.5, -0.5, 0.75);
}
// pre-drop swell
whoosh(cue.drop - 0.6, 0.62, 0.22, 400, 6000, 0, 0, 0.97);

// the year falls, today's square flies to the menu bar
whoosh(cue.collapse, 0.5, 0.16, 1800, 300, -0.3, 0.1, 0.4);
whoosh(cue.collapse + 0.12, cue.board - cue.collapse - 0.08, 0.2, 500, 5200, 0, 0.6, 0.9);
blip(cue.board, 880, 1320, 0.1, 0.07, 0.6);

// popover click
tick(cue.click - 0.01, 0.12, 2600, 0.6);
blip(cue.click, 520, 980, 0.1, 0.05, 0.5);
whoosh(cue.click, 0.3, 0.07, 3000, 900, 0.5, 0.4, 0.15);

// climb 1: two places at once
[0, 1, 2].forEach((k) => blip(cue.climb1 + k * 0.045, NOTE(["C6", "E6", "G6"][k]), undefined, 0.08, 0.09, 0.3));
whoosh(cue.climb1 - 0.05, 0.4, 0.08, 600, 2400, 0.4, 0.2, 0.3);
for (let k = 0; k < 6; k++) tick(cue.climb1 - 0.24 + k * 0.04, 0.035, 4200, 0.4);

// mvanhorn passes you
blip(cue.passed, NOTE("E5"), NOTE("C5"), 0.09, 0.14, -0.2);
blip(cue.passed + 0.12, NOTE("C5"), NOTE("A4"), 0.07, 0.16, -0.2);
whoosh(cue.passed - 0.05, 0.35, 0.07, 2000, 500, -0.2, 0.3, 0.3);

// climb 2: the big count-up, then the win
{
  const t0 = cue.climb2 - 0.36;
  for (let k = 0; k < 22; k++) {
    const p = k / 21;
    tick(t0 + 0.36 * (1 - Math.pow(1 - p, 2.2)), 0.03 + 0.02 * p, 3600 + 1400 * p, 0.35);
  }
  ["C6", "E6", "G6", "C7"].forEach((n, k) => bell(cue.climb2 + k * 0.05, NOTE(n), 0.07, 0.2 + k * 0.1, 4.5, 0.5));
  whoosh(cue.climb2 - 0.2, 0.45, 0.1, 400, 4000, 0, 0.3, 0.45);
}

// rack focus into the notification hero
whoosh(cue.nudge - 0.3, 0.7, 0.18, 2500, 200, 0.4, -0.1, 0.45);
// "mvanhorn passed you" — muted two-note
bell(cue.nudge + 0.02, NOTE("E5"), 0.09, 0.15, 5, 0.4, 1.5);
bell(cue.nudge + 0.14, NOTE("C5"), 0.08, 0.15, 5, 0.4, 1.5);
// "You passed mvanhorn!" — bright ding-ding
bell(cue.nudge2, NOTE("E6"), 0.14, 0.1, 3.2, 0.5);
bell(cue.nudge2 + 0.11, NOTE("B6"), 0.13, 0.15, 2.6, 0.55);

// hard cut to the windows
{
  const n = noiseGen();
  const hp = new Biquad("hp", 3000);
  const i0 = S(cue.windows - 0.004);
  for (let k = 0; k < S(0.09); k++) put(fx, i0 + k, hp.run(n()) * Math.exp(-(k / SR) * 60) * 0.12);
}
// segment changes and their counters
for (const [t, dur, f] of [
  [cue.week, 0.36, 3400],
  [cue.month, 0.39, 4200],
]) {
  tick(t - 0.01, 0.1, 2200, 0);
  blip(t, 700, 1050, 0.08, 0.05);
  for (let k = 0; k < 18; k++) {
    const p = k / 17;
    tick(t + dur * (1 - Math.pow(1 - p, 3)), 0.03, f + 900 * p, (k % 2 ? 0.25 : -0.25));
  }
}

// the build: riser + glitter as squares land
{
  const n = noiseGen();
  const bp = new Biquad("bp", 300, 2.2);
  const i0 = S(cue.build);
  const len = S(cue.gap - cue.build);
  let ph = 0;
  for (let k = 0; k < len; k++) {
    const p = k / len;
    if (k % 32 === 0) bp.set(300 * Math.pow(8000 / 300, p), 2.2);
    ph += (TAU * (110 * Math.pow(8, p))) / SR;
    const v = (bp.run(n()) * 0.9 + Math.sin(ph) * 0.06 * p) * Math.pow(p, 2.2) * 0.35;
    put(fx, i0 + k, v, Math.sin(p * 9) * 0.3);
    if (i0 + k < N) {
      send[0][i0 + k] += v * 0.3;
      send[1][i0 + k] += v * 0.3;
    }
  }
  const r = rngFrom(4242);
  const scale = ["A6", "C7", "D7", "E7", "G7", "A7"].map(NOTE);
  for (let k = 0; k < 64; k++) {
    const p = k / 63;
    const t = cue.build + 0.2 + 1.0 * Math.pow(p, 0.9) + r() * 0.04;
    bell(t, scale[Math.floor(r() * scale.length)], 0.018 + 0.012 * p, r() * 1.6 - 0.8, 9, 0.8);
  }
  // glint across the finished trophy
  ["E7", "G7", "A7", "C8"].forEach((nm, k) => bell(at(7, 3, 0.5) + k * 0.06, NOTE(nm), 0.035, -0.6 + k * 0.4, 6, 0.9));
}
// reverse swell into the impact
{
  const n = noiseGen();
  const hp = new Biquad("hp", 3500);
  const i0 = S(cue.gap);
  const len = S(cue.impact - cue.gap) - 40;
  for (let k = 0; k < len; k++) {
    const p = k / len;
    put(fx, i0 + k, hp.run(n()) * Math.pow(p, 3.2) * 0.32);
  }
}

// impact + resolve
kick(cue.impact, 1.15);
sub(cue.impact, 62, 36, 1.9, 0.55);
{
  const n = noiseGen();
  const lp = new Biquad("lp", 6000, 0.9);
  const i0 = S(cue.impact);
  for (let k = 0; k < S(1.2); k++) {
    const tt = k / SR;
    if (k % 32 === 0) lp.set(200 + 6000 * Math.exp(-tt * 5), 0.9);
    const v = lp.run(n()) * Math.exp(-tt * 4.5) * 0.3;
    put(fx, i0 + k, v);
    if (i0 + k < N) {
      send[0][i0 + k] += v * 0.8;
      send[1][i0 + k] += v * 0.8;
    }
  }
}
// mosaic resolves (three digital ticks), then the chord
[0.012, 0.045, 0.078].forEach((d, k) => blip(cue.impact + d, 1600 + k * 500, 2400 + k * 700, 0.05, 0.03, (k - 1) * 0.4));
pad(cue.impact, T.DURATION, hz(CH.Cfinal), 0.07, () => 3200, 0.03, 0.3);
["C6", "E6", "G6", "C7", "E7"].forEach((nm, k) => bell(cue.impact + 0.02 + k * 0.045, NOTE(nm), 0.075 - k * 0.008, -0.5 + k * 0.25, 1.6, 0.7));
bell(at(8, 3, 0.25), NOTE("G7"), 0.03, 0.4, 3, 0.9); // end-card shine
// a soft arpeggio keeps the end card breathing
["C5", "E5", "G5", "C6", "E6", "G5", "C6", "E6"].forEach((nm, k) =>
  pluck(at(8, 2, k / 2), NOTE(nm), 0.035 * (1 - k / 12), k % 2 ? 0.35 : -0.35),
);

// ---------- mix ----------
// sidechain: music ducks under every kick (and the impact)
const duck = new Float32Array(N).fill(1);
for (const t of [...T.kicks, cue.impact]) {
  const i0 = S(t);
  for (let k = 0; k < S(BEAT); k++) {
    const tt = k / SR;
    const g = 1 - 0.78 * Math.min(1, tt / 0.004) * Math.exp(-tt * 9);
    if (i0 + k < N) duck[i0 + k] = Math.min(duck[i0 + k], g);
  }
}

// Freeverb-style reverb on the send bus
function freeverb(input, spread) {
  const scale = SR / 44100;
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((d) => {
    const len = Math.round((d + spread) * scale);
    return { buf: new Float32Array(len), i: 0, store: 0 };
  });
  const aps = [556, 441, 341, 225].map((d) => ({ buf: new Float32Array(Math.round((d + spread) * scale)), i: 0 }));
  const out = new Float32Array(N);
  const fb = 0.86;
  const damp = 0.25;
  for (let n = 0; n < N; n++) {
    const x = input[n] * 0.015;
    let y = 0;
    for (const c of combs) {
      const o = c.buf[c.i];
      c.store = o * (1 - damp) + c.store * damp;
      c.buf[c.i] = x + c.store * fb;
      if (++c.i >= c.buf.length) c.i = 0;
      y += o;
    }
    for (const a of aps) {
      const b = a.buf[a.i];
      a.buf[a.i] = y + b * 0.5;
      if (++a.i >= a.buf.length) a.i = 0;
      y = b - y;
    }
    out[n] = y;
  }
  return out;
}
const revL = freeverb(send[0], 0);
const revR = freeverb(send[1], 23);

const outL = new Float32Array(N);
const outR = new Float32Array(N);
const hpL = new Biquad("hp", 28);
const hpR = new Biquad("hp", 28);
for (let n = 0; n < N; n++) {
  const t = n / SR;
  let l = drums[0][n] * 0.74 + music[0][n] * duck[n] * 1.12 + fx[0][n] * 0.9 + revL[n] * 1.1;
  let r = drums[1][n] * 0.74 + music[1][n] * duck[n] * 1.12 + fx[1][n] * 0.9 + revR[n] * 1.1;
  // tail fade over the last half second
  const fade = t > T.DURATION - 0.5 ? Math.cos(((t - (T.DURATION - 0.5)) / 0.5) * (Math.PI / 2)) : 1;
  outL[n] = hpL.run(l) * fade;
  outR[n] = hpR.run(r) * fade;
}
// glue: soft clip, then normalize to -1 dBFS
let peak = 0;
for (let n = 0; n < N; n++) {
  outL[n] = Math.tanh(outL[n] * 1.25);
  outR[n] = Math.tanh(outR[n] * 1.25);
  peak = Math.max(peak, Math.abs(outL[n]), Math.abs(outR[n]));
}
const gain = Math.pow(10, -1 / 20) / peak;

const dataLen = N * 4;
const wav = Buffer.alloc(44 + dataLen);
wav.write("RIFF", 0);
wav.writeUInt32LE(36 + dataLen, 4);
wav.write("WAVE", 8);
wav.write("fmt ", 12);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(2, 22);
wav.writeUInt32LE(SR, 24);
wav.writeUInt32LE(SR * 4, 28);
wav.writeUInt16LE(4, 32);
wav.writeUInt16LE(16, 34);
wav.write("data", 36);
wav.writeUInt32LE(dataLen, 40);
for (let n = 0; n < N; n++) {
  wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, outL[n] * gain)) * 32767), 44 + n * 4);
  wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, outR[n] * gain)) * 32767), 46 + n * 4);
}
const dir = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(dir, "..", "assets", "score.wav");
writeFileSync(out, wav);
console.log(`wrote ${path.relative(process.cwd(), out)} — ${T.DURATION}s, ${SR} Hz, peak normalized from ${peak.toFixed(3)}`);

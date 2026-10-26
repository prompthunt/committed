"use client";

import { useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";
import { useMotionPaused } from "./useLoop";

/*
 * Design exploration: a field of contribution squares behind the hero desktop, lit the way
 * raycast.com lights its hero. Raycast renders a three.js scene: a cube running a cosine
 * interference gradient, seen through a row of glass rods tilted 0.73 rad. Here one fragment
 * shader draws every variant on a single canvas, driven by the same interference function.
 *
 * Diamond is the user's follow-up idea: big squares forming a diamond whose top sits behind the
 * headline and whose widest rows fade out behind the desk.
 *
 * The switcher (bottom of the page, keys 1–6, or ?bg=<id>) flips between them for review.
 * Once one is picked, keep that variant, delete the rest and the switcher.
 */

export const VARIANTS = [
  { id: "diamond", label: "Diamond" },
  { id: "glass", label: "Glass" },
  { id: "calendar", label: "Calendar" },
  { id: "pulse", label: "Pulse" },
  { id: "floor", label: "Floor" },
  { id: "off", label: "Off" },
] as const;

type VariantId = (typeof VARIANTS)[number]["id"];
const isVariant = (v: string | null): v is VariantId => VARIANTS.some((x) => x.id === v);

const VERTEX = `#version 300 es
void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

const FRAGMENT = `#version 300 es
precision highp float;
uniform vec2 uRes;    // canvas size, CSS px
uniform float uPx;    // device px per CSS px
uniform float uTime;  // seconds
uniform int uMode;
uniform vec4 uDesk;   // desk rect in CSS px, GL orientation: x, y (bottom), w, h
uniform vec4 uHead;   // headline rect, same orientation (diamond only)
uniform float uPitch; // diamond square pitch, CSS px
out vec4 outColor;

const vec3 INK = vec3(0.0196);
const vec3 SQ[5] = vec3[5](
  vec3(0.078, 0.090, 0.059), vec3(0.114, 0.180, 0.055), vec3(0.208, 0.361, 0.071),
  vec3(0.416, 0.659, 0.102), vec3(0.784, 1.0, 0.180));
const vec3 HOT = vec3(0.94, 1.0, 0.80);
const float PITCH = 19.0;
const float HALF = 7.5;
const float RADIUS = 3.0;

vec3 level(float l) { return SQ[int(clamp(l, 0.0, 4.0))]; }

// The calendar ramp, eased between levels so animated squares fade instead of popping.
vec3 ramp(float v) {
  float f = clamp(v, 0.0, 0.9999) * 4.0;
  float i = floor(f);
  return mix(level(i), level(i + 1.0), smoothstep(0.7, 1.0, f - i));
}

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

// Raycast's hero gradient: horizontal, diagonal and radial cosine waves, averaged to 0..1.
float wave(vec2 xy, float t) {
  float h = cos(3.0 * xy.x + t);
  float d = cos(xy.x * cos(t) + 5.0 * xy.y * sin(t) + t);
  float x = 0.3 * xy.x - 0.5 + cos(t);
  float y = 0.3 * xy.y - 0.5 + sin(t * 0.5);
  float r = sin(20.0 * sqrt(x * x + y * y + 1.0) + t);
  return ((h + d + r) / 3.0 + 1.0) * 0.5;
}

vec2 deskCenter() { return uDesk.xy + uDesk.zw * 0.5; }

float rectDist(vec2 p, vec4 r) {
  vec2 d = abs(p - r.xy - r.zw * 0.5) - r.zw * 0.5;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float deskDist(vec2 p) { return rectDist(p, uDesk); }

float roundSquare(vec2 q, float size, float r) {
  vec2 d = abs(q) - vec2(size - r);
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float coverage(float sd, float aa) { return clamp(0.5 - sd / aa, 0.0, 1.0); }

// Squares on a grid centred on the desk: returns the cell index, writes its centre.
vec2 cellAt(vec2 p, out vec2 centre) {
  vec2 cell = floor((p - deskCenter()) / PITCH + 0.5);
  centre = deskCenter() + cell * PITCH;
  return cell;
}

float halo(vec2 p, float reach) { return exp(-max(deskDist(p), 0.0) / reach); }

// 1 · Glass: lit squares in a slab behind the desk, seen through tilted glass rods.
vec3 slab(vec2 p, float t) {
  vec2 c;
  cellAt(p, c);
  float v = wave(c / uRes * 1.6, t);
  vec3 col = mix(SQ[1], SQ[3], smoothstep(0.25, 0.6, v));
  col = mix(col, SQ[4], smoothstep(0.6, 0.85, v));
  col = mix(col, HOT, smoothstep(0.85, 1.0, v));
  // A hard-edged slab a little larger than the desk; the rods break its edge into bars.
  float d = deskDist(c);
  float light = (1.0 - smoothstep(20.0, 110.0, d)) * 0.85 + 0.15 * exp(-max(d, 0.0) / 140.0);
  return col * light * coverage(roundSquare(p - c, HALF, RADIUS), 1.5);
}

vec3 glass(vec2 p) {
  const float A = 0.73;
  const float W = 92.0;
  vec2 across = vec2(cos(A), sin(A));
  vec2 along = vec2(-across.y, across.x);
  float t = uTime * 0.1 + 30.0;
  float u = fract(dot(p - deskCenter(), across) / W) * 2.0 - 1.0;
  vec2 bend = across * (-u * W * 0.45 / sqrt(1.0 - 0.8 * u * u));
  vec3 acc = vec3(0.0);
  for (int j = 0; j < 4; j++) {
    vec2 q = p + along * ((float(j) - 1.5) * 6.0);
    acc.r += slab(q + bend * 1.00, t).r;
    acc.g += slab(q + bend * 1.03, t).g;
    acc.b += slab(q + bend * 1.06, t).b;
  }
  acc *= 0.25 * (0.55 + 0.45 * sqrt(max(1.0 - u * u, 0.0)));
  float rim = exp(-pow((u + 0.55) * 7.0, 2.0)) * 0.035 * halo(p, 420.0);
  return INK + acc + rim;
}

// 2 · Calendar: a living contribution graph, only the five real square colours.
vec3 calendar(vec2 p) {
  vec2 c;
  vec2 cell = cellAt(p, c);
  float glow = halo(c, 240.0);
  float v = wave(c / uRes, uTime * 0.12 + 40.0);
  float e = (v * 0.8 + hash(cell) * 0.45 - 0.25) * (0.35 + 0.9 * glow);
  float vis = smoothstep(0.02, 0.35, glow);
  return mix(INK, ramp(e), coverage(roundSquare(p - c, HALF, RADIUS), 1.0 / uPx) * vis);
}

// 3 · Pulse: rings of light leave the desk's edge, like a push landing.
vec3 pulse(vec2 p) {
  vec2 c;
  vec2 cell = cellAt(p, c);
  float n = hash(cell);
  float n2 = hash(cell + 17.3);
  float d = deskDist(c);
  float glow = halo(c, 240.0);
  float base = n < 0.55 ? 0.0 : n < 0.8 ? 1.0 : n < 0.94 ? 2.0 : 3.0;
  float lit = 0.0;
  for (int k = 0; k < 3; k++) {
    float ph = fract(uTime / 5.4 + float(k) / 3.0);
    float ring = exp(-pow((d - ph * 950.0 + 30.0) / (28.0 + ph * 50.0), 2.0));
    lit = max(lit, ring * (1.0 - ph) * (1.0 - ph));
  }
  lit *= step(0.5, n2) * (0.55 + 0.45 * n2);
  float l = max(base * 0.25 * smoothstep(0.0, 0.7, glow), lit * 1.15);
  vec3 col = mix(ramp(l), HOT, smoothstep(0.75, 1.0, lit));
  float vis = smoothstep(0.0, 0.3, max(glow, lit));
  return mix(INK, col, coverage(roundSquare(p - c, HALF, RADIUS), 1.0 / uPx) * vis);
}

// 4 · Floor: the desk stands on a calendar receding to a horizon behind it.
vec3 floorGrid(vec2 p) {
  vec2 dc = deskCenter();
  float horizon = uDesk.y + uDesk.w * 0.42;
  float dy = horizon - p.y;
  float spread = exp(-pow((p.x - dc.x) / (uDesk.z * 0.8), 2.0));
  vec3 col = INK + SQ[4] * exp(-abs(dy) / 110.0) * spread * 0.10;
  if (dy <= 1.0) return col;
  vec2 w = vec2((p.x - dc.x) * 9.0 / dy, 5200.0 / dy - uTime * 0.6);
  vec2 cell = floor(w);
  float sd = roundSquare(fract(w) - 0.5, 0.39, 0.1);
  float aa = max(fwidth(sd), 1e-4);
  float cov = coverage(sd, aa) * (1.0 - smoothstep(0.15, 0.45, aa));
  float v = wave(cell * vec2(0.035, 0.05), uTime * 0.12 + 20.0);
  float e = v * 0.75 + hash(cell) * 0.45 - 0.3;
  float fog = smoothstep(6.0, 90.0, dy);
  return mix(col, ramp(e), cov * fog * (0.35 + 0.65 * spread));
}

// 5 · Diamond: six columns of big squares stacked into a diamond above the desk. Its top row
// sits behind the headline; its widest rows fade out as they slide behind the desk.
vec3 diamond(vec2 p) {
  float deskTop = uDesk.y + uDesk.w;
  vec2 o = vec2(deskCenter().x, deskTop);
  vec2 cell = floor((p - o) / uPitch);
  vec2 local = p - o - (cell + 0.5) * uPitch;
  vec2 c = o + (cell + 0.5) * uPitch;
  // Rows counted up from the desk: widths 6, 6, 4, 2, and 4, 2 continuing behind it.
  float shape = abs(cell.x + 0.5) + max(cell.y - 1.0, -cell.y);
  if (shape > 2.5) return INK;
  float n = hash(cell + 3.1);
  float v = wave(c / uRes * 1.2, uTime * 0.12 + 50.0);
  float e = 0.16 + 0.36 * v + 0.26 * n + 0.24 * step(2.0, shape);
  // Keep the hero copy legible: dim squares in the column from the headline down to the desk.
  float top = uHead.y + uHead.w;
  e *= 1.0 - 0.55 * exp(-max(rectDist(c, vec4(uHead.x, deskTop, uHead.z, top - deskTop)), 0.0) / (0.3 * uPitch));
  e *= smoothstep(deskTop - 0.3 * uPitch, deskTop + 0.9 * uPitch, p.y);
  float cov = coverage(roundSquare(local, uPitch * 0.435, max(2.0, uPitch * 0.02)), 1.0 / uPx);
  return mix(INK, mix(ramp(e), HOT, smoothstep(0.9, 1.0, e)), cov * smoothstep(0.02, 0.1, e));
}

void main() {
  vec2 p = gl_FragCoord.xy / uPx;
  vec3 col;
  if (uMode == 0) col = diamond(p);
  else if (uMode == 1) col = glass(p);
  else if (uMode == 2) col = calendar(p);
  else if (uMode == 3) col = pulse(p);
  else col = floorGrid(p);
  outColor = vec4(col, 1.0);
}`;

function compile(gl: WebGL2RenderingContext, type: number, source: string) {
  const shader = gl.createShader(type)!;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) ?? "shader");
  return shader;
}

// Canvas extents for the desk-only variants; the diamond also reaches up behind the headline.
const BELOW = "clamp(120px,16vw,280px)";
const HEAD_PAD = 180;

function Field({ mode, around }: { mode: number; around: RefObject<HTMLDivElement | null> }) {
  const tall = mode === 0;
  const ref = useRef<HTMLCanvasElement>(null);
  const paused = useMotionPaused();
  const pausedRef = useRef(paused);
  const kick = useRef<() => void>(() => {});

  useEffect(() => {
    pausedRef.current = paused;
    kick.current();
  }, [paused]);

  useEffect(() => {
    const canvas = ref.current;
    const gl = canvas?.getContext("webgl2", { antialias: false, powerPreference: "low-power" });
    if (!canvas || !gl) return;

    let program: WebGLProgram;
    try {
      program = gl.createProgram()!;
      gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERTEX));
      gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAGMENT));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) ?? "link");
    } catch (error) {
      console.warn("SquareField:", error);
      return;
    }
    gl.useProgram(program);
    const u = (name: string) => gl.getUniformLocation(program, name);
    const uRes = u("uRes"), uPx = u("uPx"), uTime = u("uTime"), uMode = u("uMode"), uDesk = u("uDesk");
    const uHead = u("uHead"), uPitch = u("uPitch");
    gl.uniform1i(uMode, mode);

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
    let onScreen = true;
    let raf = 0;
    let clock = 8;
    let last = 0;
    // Like Raycast's hero, give up on motion where the GPU can't keep up: hold a still frame.
    let slow = false;
    let frames = 0;
    let since = 0;

    const measure = () => {
      const wrap = around.current;
      const desk = wrap?.querySelector(".desk-frame");
      if (!wrap || !desk) return;
      // Offsets ignore transforms, so the headline's rise animation doesn't skew the measurement.
      const head = document.querySelector<HTMLElement>("main h1");
      if (tall && head) {
        const above = wrap.offsetTop - head.offsetTop + HEAD_PAD;
        canvas.style.top = `${-above}px`;
        canvas.style.height = `calc(100% + ${above}px + ${BELOW})`;
      }
      // The glass variant is blurred anyway, so it renders at 1x to keep its 12 samples cheap.
      const px = mode === 1 ? 1 : Math.min(window.devicePixelRatio || 1, 1.5);
      const box = canvas.getBoundingClientRect();
      const d = desk.getBoundingClientRect();
      canvas.width = Math.round(box.width * px);
      canvas.height = Math.round(box.height * px);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(uRes, box.width, box.height);
      gl.uniform1f(uPx, canvas.width / box.width);
      gl.uniform4f(uDesk, d.left - box.left, box.bottom - d.bottom, d.width, d.height);
      if (head) gl.uniform4f(uHead, (box.width - head.offsetWidth) / 2, box.height - HEAD_PAD - head.offsetHeight, head.offsetWidth, head.offsetHeight);
      // Six columns, and four rows between the header and the desk.
      const headerBottom = document.querySelector("header")?.getBoundingClientRect().bottom ?? 0;
      gl.uniform1f(uPitch, Math.min(box.width / 6.5, (d.top - headerBottom) / 4, 160));
    };

    const draw = () => {
      gl.uniform1f(uTime, clock);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };

    const tick = (now: number) => {
      clock += Math.min(now - last, 100) / 1000;
      last = now;
      draw();
      if (++frames === 1) since = now;
      if (frames === 60 && now - since > 59 * 50) {
        slow = true;
        return;
      }
      raf = requestAnimationFrame(tick);
    };

    // Run only while visible and allowed to move; otherwise hold the current frame.
    const update = () => {
      cancelAnimationFrame(raf);
      raf = 0;
      if (onScreen && !slow && !document.hidden && !reduce.matches && !pausedRef.current) {
        last = performance.now();
        frames = 0;
        raf = requestAnimationFrame(tick);
      } else {
        draw();
      }
    };
    kick.current = update;

    const ro = new ResizeObserver(() => {
      measure();
      draw();
    });
    ro.observe(canvas);
    const desk = around.current?.querySelector(".desk-frame");
    if (desk) ro.observe(desk);
    const io = new IntersectionObserver(([entry]) => {
      onScreen = entry.isIntersecting;
      update();
    });
    io.observe(canvas);
    document.addEventListener("visibilitychange", update);
    reduce.addEventListener("change", update);
    measure();
    update();

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      io.disconnect();
      document.removeEventListener("visibilitychange", update);
      reduce.removeEventListener("change", update);
      kick.current = () => {};
      gl.deleteProgram(program);
    };
  }, [mode, tall, around]);

  return (
    <canvas
      ref={ref}
      aria-hidden
      className={`pointer-events-none absolute left-1/2 -z-10 w-screen -translate-x-1/2 ${
        tall
          ? "[mask-image:linear-gradient(to_bottom,transparent,#000_4%)]"
          : "-top-[clamp(100px,14vw,220px)] h-[calc(100%+clamp(100px,14vw,220px)+clamp(120px,16vw,280px))] [mask-image:linear-gradient(to_bottom,transparent,#000_22%,#000_78%,transparent)]"
      }`}
    />
  );
}

/** Wraps the hero desktop with the square field behind it, plus the temporary variant switcher. */
export function SquareField({ children }: { children: ReactNode }) {
  const around = useRef<HTMLDivElement>(null);
  const [variant, setVariant] = useState<VariantId>("diamond");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const fromUrl = new URLSearchParams(window.location.search).get("bg");
    if (isVariant(fromUrl)) setVariant(fromUrl);
    setMounted(true);
  }, []);

  const choose = (id: VariantId) => {
    setVariant(id);
    const url = new URL(window.location.href);
    url.searchParams.set("bg", id);
    window.history.replaceState(null, "", url);
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey || event.target instanceof HTMLInputElement) return;
      const next = VARIANTS[Number(event.key) - 1];
      if (next) choose(next.id);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const mode = VARIANTS.findIndex((v) => v.id === variant);
  return (
    <div ref={around} className="relative mb-[clamp(120px,16vw,280px)]">
      {variant !== "off" && <Field key={variant} mode={mode} around={around} />}
      {children}
      {mounted && createPortal(<Switcher value={variant} onChange={choose} />, document.body)}
    </div>
  );
}

function Switcher({ value, onChange }: { value: VariantId; onChange: (id: VariantId) => void }) {
  return (
    <div className="fixed bottom-5 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-white/10 bg-[#0b0d08]/85 p-1 pl-4 text-[13px] shadow-[0_20px_60px_-20px_#000] backdrop-blur-xl max-sm:pl-1">
      <span className="mr-2 text-muted max-sm:hidden">Background</span>
      {VARIANTS.map((v, i) => (
        <button
          key={v.id}
          type="button"
          onClick={() => onChange(v.id)}
          aria-pressed={value === v.id}
          className={`flex h-9 items-center gap-1.5 rounded-full px-3.5 font-medium transition-colors max-sm:px-2.5 ${
            value === v.id ? "bg-lime text-ink" : "text-soft hover:bg-white/[.07] hover:text-white"
          }`}
        >
          <span className={`text-[11px] tabular-nums max-sm:hidden ${value === v.id ? "text-ink/55" : "text-faint"}`}>{i + 1}</span>
          {v.label}
        </button>
      ))}
    </div>
  );
}

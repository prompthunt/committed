"use client";

import { useEffect, useRef, type ReactNode, type RefObject } from "react";
import { useMotionPaused } from "./useLoop";

/*
 * A grid of contribution squares behind the hero, lit the way raycast.com lights its hero.
 * Raycast renders a three.js scene: a cube running a cosine interference gradient, seen through
 * glass rods. Here one fragment shader draws a calendar grid lit by a compact glow just above the
 * desk; each square bends the glow like a small glass tile. The desk covers the glow's lower half.
 */

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
uniform vec4 uDesk;   // desk rect in CSS px, GL orientation: x, y (bottom), w, h
uniform vec4 uHead;   // headline rect, same orientation
uniform vec4 uCopy;   // headline down to the download caption, same orientation
out vec4 outColor;

const vec3 INK = vec3(0.0196);
const vec3 SQ[5] = vec3[5](
  vec3(0.078, 0.090, 0.059), vec3(0.114, 0.180, 0.055), vec3(0.208, 0.361, 0.071),
  vec3(0.416, 0.659, 0.102), vec3(0.784, 1.0, 0.180));
const vec3 HOT = vec3(0.94, 1.0, 0.80);

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

float rectDist(vec2 p, vec4 r) {
  vec2 d = abs(p - r.xy - r.zw * 0.5) - r.zw * 0.5;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float roundSquare(vec2 q, float size, float r) {
  vec2 d = abs(q) - vec2(size - r);
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float coverage(float sd, float aa) { return clamp(0.5 - sd / aa, 0.0, 1.0); }

// Like Raycast's cube, the light is about a third of the screen wide and black around it. It sits
// just above the desk's top edge, so the desk covers its lower half, and drifts slowly.
float lamp(vec2 c, float t) {
  float y = mix(uDesk.y + uDesk.w, uHead.y + uHead.w * 0.5, 0.3);
  vec2 centre = vec2(uHead.x + uHead.z * 0.5, y) + vec2(sin(t * 3.0), cos(t * 2.3)) * 40.0;
  float rx = clamp(uRes.x * 0.22, 170.0, 480.0);
  vec2 q = (c - centre) / vec2(rx, rx * 0.85);
  return exp(-dot(q, q) * 1.4);
}

// Raycast cubes its colour; the power keeps the falloff tight so the glow's edge drops to black.
float glowAt(vec2 c, float t) {
  // On phones the glow fills the screen behind the headline, so it runs dimmer there.
  return pow(lamp(c, t), 1.5) * 1.5 * mix(0.6, 1.0, smoothstep(420.0, 1000.0, uRes.x));
}

void main() {
  vec2 p = gl_FragCoord.xy / uPx;
  float t = uTime * 0.1 + 30.0;
  float s = clamp(uRes.x * 0.028, 26.0, 44.0);
  vec2 o = uHead.xy + uHead.zw * 0.5;
  vec2 cell = floor((p - o) / s + 0.5);
  vec2 l = p - o - cell * s;
  vec2 centre = o + cell * s;
  float hs = s * 0.42;
  float sd = roundSquare(l, hs, s * 0.14);
  // Each square is its own calendar level, drifting with the wave.
  float e = wave(centre / uRes * 1.6, uTime * 0.12 + 40.0) * 0.7 + hash(cell) * 0.5 - 0.2;
  vec3 col = ramp(e);
  // Each square bends the glow behind it like a pillow lens, split slightly by channel.
  vec2 u = clamp(l / hs, -0.999, 0.999);
  vec2 bend = -u * s * 0.32 / sqrt(1.0 - 0.8 * u * u);
  vec3 lum = vec3(glowAt(p + bend, t), glowAt(p + bend * 1.05, t), glowAt(p + bend * 1.1, t));
  float m = max(abs(u.x), abs(u.y));
  vec3 lit = (col + HOT * 0.35 * smoothstep(0.85, 1.0, e)) * lum * (0.6 + 0.4 * (1.0 - m * m * m * m));
  // A rim highlight on each square's upper-left edge.
  float edge = smoothstep(-s * 0.12, -0.8, sd) * max(dot(normalize(l + 1e-4), vec2(-0.7071, 0.7071)), 0.0);
  lit += edge * (0.02 + 0.5 * lamp(p, t)) * HOT * 0.25;
  // Bright lime squares swallow the lime "today?" and the small caption, so the glow dips behind the copy.
  lit *= 1.0 - 0.55 * exp(-max(rectDist(centre, uCopy), 0.0) / 40.0);
  outColor = vec4(INK + lit * coverage(sd, 1.0 / uPx), 1.0);
}`;

function compile(gl: WebGL2RenderingContext, type: number, source: string) {
  const shader = gl.createShader(type)!;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader) ?? "shader");
  return shader;
}

// The canvas reaches from above the headline to below the desk.
const BELOW = "clamp(120px,16vw,280px)";
const HEAD_PAD = 180;

function Field({ around }: { around: RefObject<HTMLDivElement | null> }) {
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
    const uRes = u("uRes"), uPx = u("uPx"), uTime = u("uTime"), uDesk = u("uDesk");
    const uHead = u("uHead"), uCopy = u("uCopy");

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
      // Offsets ignore transforms, so the headline's rise animation doesn't skew the measurement.
      const head = document.querySelector<HTMLElement>("main h1");
      if (!wrap || !desk || !head) return;
      const above = wrap.offsetTop - head.offsetTop + HEAD_PAD;
      canvas.style.top = `${-above}px`;
      canvas.style.height = `calc(100% + ${above}px + ${BELOW})`;
      const px = Math.min(window.devicePixelRatio || 1, 1.5);
      const box = canvas.getBoundingClientRect();
      const d = desk.getBoundingClientRect();
      canvas.width = Math.round(box.width * px);
      canvas.height = Math.round(box.height * px);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(uRes, box.width, box.height);
      gl.uniform1f(uPx, canvas.width / box.width);
      gl.uniform4f(uDesk, d.left - box.left, box.bottom - d.bottom, d.width, d.height);
      const x = (box.width - head.offsetWidth) / 2;
      gl.uniform4f(uHead, x, box.height - HEAD_PAD - head.offsetHeight, head.offsetWidth, head.offsetHeight);
      const lastCopy = head.parentElement?.lastElementChild as HTMLElement | null;
      const copy = lastCopy ? lastCopy.offsetTop + lastCopy.offsetHeight - head.offsetTop : head.offsetHeight;
      gl.uniform4f(uCopy, x, box.height - HEAD_PAD - copy, head.offsetWidth, copy);
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
  }, [around]);

  return (
    <canvas
      ref={ref}
      aria-hidden
      className="pointer-events-none absolute left-1/2 -z-10 w-screen -translate-x-1/2 opacity-50 [mask-image:linear-gradient(to_bottom,transparent,#000_4%)]"
    />
  );
}

/** Wraps the hero desktop with the square field behind it. */
export function SquareField({ children }: { children: ReactNode }) {
  const around = useRef<HTMLDivElement>(null);
  return (
    <div ref={around} className="relative mb-[clamp(72px,8vw,128px)]">
      <Field around={around} />
      {children}
    </div>
  );
}

"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { seeded } from "@/lib/contributions";

/*
 * Design exploration: five treatments for the light behind the hero popover.
 * BackdropSwitcher (bottom of the page, keys 1–5, or ?bg=<id>) flips between them.
 * Once one is picked, keep that variant, delete the rest and the switcher.
 */

export const VARIANTS = [
  { id: "aura", label: "Aura" },
  { id: "mesh", label: "Mesh" },
  { id: "spotlight", label: "Spotlight" },
  { id: "track", label: "Track" },
  { id: "aurora", label: "Aurora" },
] as const;

type VariantId = (typeof VARIANTS)[number]["id"];
const isVariant = (v: string | null): v is VariantId => VARIANTS.some((x) => x.id === v);

export function HeroBackdrop() {
  const [variant, setVariant] = useState<VariantId>("aura");
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
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const v = VARIANTS[Number(e.key) - 1];
      if (v) choose(v.id);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <>
      <div className="pointer-events-none absolute top-[54%] left-1/2 h-[860px] w-[920px] -translate-x-1/2 -translate-y-1/2">
        {variant === "aura" && <Aura />}
        {variant === "mesh" && <Mesh />}
        {variant === "spotlight" && <Spotlight />}
        {variant === "track" && <Track />}
        {variant === "aurora" && <Aurora />}
      </div>
      {mounted && createPortal(<Switcher value={variant} onChange={choose} />, document.body)}
    </>
  );
}

function Switcher({ value, onChange }: { value: VariantId; onChange: (id: VariantId) => void }) {
  return (
    <div className="fixed bottom-5 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-white/10 bg-[#0b0d08]/85 p-1 pl-4 text-[13px] shadow-[0_20px_60px_-20px_#000] backdrop-blur-xl max-sm:pl-1">
      <span className="mr-2 text-muted max-sm:hidden">Backdrop</span>
      {VARIANTS.map((v, i) => (
        <button
          key={v.id}
          type="button"
          onClick={() => onChange(v.id)}
          aria-pressed={value === v.id}
          className={`flex h-9 items-center gap-1.5 rounded-full px-3.5 font-medium max-sm:px-2.5 transition-colors ${
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

/* 1 · Aura — a breathing core of lime light with slow-turning rays around it. */
function Aura() {
  return (
    <div className="bd-aura absolute inset-0">
      <i className="bd-aura-rays" />
      <i className="bd-aura-core" />
      <i className="bd-aura-rim" />
      <i className="bd-aura-flare bd-aura-flare-a" />
      <i className="bd-aura-flare bd-aura-flare-b" />
    </div>
  );
}

/* 2 · Mesh — drifting gradient blobs across the green ramp, with film grain. */
function Mesh() {
  return (
    <div className="bd-mesh absolute inset-0">
      <i style={{ ["--x" as string]: "58%", ["--y" as string]: "30%", ["--s" as string]: "480px", ["--c" as string]: "rgb(200 255 46 / .5)", animationName: "bd-drift-a" }} />
      <i style={{ ["--x" as string]: "30%", ["--y" as string]: "58%", ["--s" as string]: "560px", ["--c" as string]: "rgb(106 168 26 / .55)", animationName: "bd-drift-b" }} />
      <i style={{ ["--x" as string]: "72%", ["--y" as string]: "70%", ["--s" as string]: "560px", ["--c" as string]: "rgb(53 92 18 / .9)", animationName: "bd-drift-c" }} />
      <i style={{ ["--x" as string]: "38%", ["--y" as string]: "22%", ["--s" as string]: "420px", ["--c" as string]: "rgb(29 46 14 / .95)", animationName: "bd-drift-b" }} />
      <i style={{ ["--x" as string]: "64%", ["--y" as string]: "50%", ["--s" as string]: "260px", ["--c" as string]: "rgb(232 255 150 / .35)", animationName: "bd-drift-c" }} />
      <span className="bd-grain" />
    </div>
  );
}

/* 3 · Spotlight — a stage light on the leader: a beam from above, a pool of light below. */
const DUST = (() => {
  const rnd = seeded(5);
  return Array.from({ length: 34 }, () => ({
    x: 50 + (rnd() - 0.5) * 34 * (0.4 + rnd()),
    y: 12 + rnd() * 70,
    s: 1.5 + rnd() * 2.5,
    d: 6 + rnd() * 10,
    delay: -rnd() * 16,
  }));
})();

function Spotlight() {
  return (
    <div className="bd-spot absolute inset-0">
      <i className="bd-spot-beam" />
      <i className="bd-spot-beam bd-spot-beam-core" />
      <i className="bd-spot-lamp" />
      <i className="bd-spot-floor" />
      {DUST.map((p, i) => (
        <span
          key={i}
          className="bd-spot-dust"
          style={{ left: `${p.x}%`, top: `${p.y}%`, width: p.s, height: p.s, animationDuration: `${p.d}s`, animationDelay: `${p.delay}s` }}
        />
      ))}
    </div>
  );
}

/* 4 · Track — lanes radiate out from the board; racers lap them at different speeds. */
const W = 920;
const H = 860;
const CX = W / 2;
const CY = H / 2 + 20;
const lane = (i: number) => {
  const w = 360 + i * 56;
  const h = 520 + i * 56;
  const r = Math.min(26 + i * 30, w / 2);
  const x = CX - w / 2;
  const y = CY - h / 2;
  return { x, y, w, h, r };
};
const lanePath = (i: number) => {
  const { x, y, w, h, r } = lane(i);
  return `M ${x + r} ${y} H ${x + w - r} A ${r} ${r} 0 0 1 ${x + w} ${y + r} V ${y + h - r} A ${r} ${r} 0 0 1 ${x + w - r} ${y + h} H ${x + r} A ${r} ${r} 0 0 1 ${x} ${y + h - r} V ${y + r} A ${r} ${r} 0 0 1 ${x + r} ${y} Z`;
};
const LANES = Array.from({ length: 9 }, (_, i) => i);
const RACERS = [
  { lane: 1, dur: 15, delay: -3, lead: true },
  { lane: 2, dur: 18, delay: -9, lead: false },
  { lane: 4, dur: 23, delay: -14, lead: false },
  { lane: 6, dur: 29, delay: -4, lead: false },
];

function Track() {
  return (
    <div className="bd-track absolute inset-0">
      <i className="bd-track-glow" />
      <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} className="absolute inset-0" fill="none">
        {LANES.map((i) => (
          <path
            key={i}
            d={lanePath(i)}
            className="bd-track-lane"
            stroke="var(--color-lime)"
            strokeOpacity={0.5 - i * 0.045}
            strokeWidth={1}
            strokeDasharray={i % 3 === 2 ? "2 7" : undefined}
            style={{ animationDelay: `${i * 0.22}s` }}
          />
        ))}
      </svg>
      {RACERS.map((r, i) => (
        <span
          key={i}
          className={`bd-track-racer ${r.lead ? "bd-track-racer-lead" : ""}`}
          style={{ offsetPath: `path("${lanePath(r.lane)}")`, animationDuration: `${r.dur}s`, animationDelay: `${r.delay}s` }}
        />
      ))}
    </div>
  );
}

/* 5 · Aurora — a WebGL shader: slow ribbons of lime light folding through dark moss. */
const FRAG = `
precision mediump float;
uniform vec2 r;
uniform float t;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);vec2 u=f*f*(3.-2.*f);
  return mix(mix(h(i),h(i+vec2(1,0)),u.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),u.x),u.y);}
float fbm(vec2 p){float v=0.,a=.5;for(int i=0;i<5;i++){v+=a*n(p);p=p*2.03+vec2(1.7,9.2);a*=.5;}return v;}
void main(){
  vec2 uv=(gl_FragCoord.xy-.5*r)/r.y;
  float tt=t*.05;
  vec2 q=vec2(fbm(uv*1.4+vec2(tt,-tt)),fbm(uv*1.4+vec2(5.2,1.3)-tt));
  float f=fbm(uv*2.0+q*2.2+vec2(0.,tt*1.5));
  float ribbon=pow(1.-abs(sin((uv.x*.6+uv.y+q.x*1.2)*3.4+f*5.)),6.);
  float fall=smoothstep(.62,.08,length(uv*vec2(1.05,.8)));
  float v=(pow(f,2.2)*1.9+ribbon*.55*f)*fall;
  vec3 moss=vec3(.06,.13,.03),deep=vec3(.33,.58,.08),lime=vec3(.784,1.,.18);
  vec3 c=mix(moss,deep,smoothstep(.08,.4,v));
  c=mix(c,lime,smoothstep(.38,.85,v));
  float a=smoothstep(.0,.3,v)+(h(gl_FragCoord.xy+t)-.5)/96.;
  gl_FragColor=vec4(c*a,a);
}`;
const VERT = "attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}";

function Aurora() {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    const gl = canvas?.getContext("webgl", { premultipliedAlpha: true, antialias: false });
    if (!canvas || !gl) return;

    const compile = (type: number, src: string) => {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, src);
      gl.compileShader(s);
      return s;
    };
    const prog = gl.createProgram()!;
    gl.attachShader(prog, compile(gl.VERTEX_SHADER, VERT));
    gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(prog);
    gl.useProgram(prog);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, "p");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const uR = gl.getUniformLocation(prog, "r");
    const uT = gl.getUniformLocation(prog, "t");

    // The light is soft, so half resolution is indistinguishable and a quarter of the cost.
    const scale = Math.min(window.devicePixelRatio, 2) * 0.5;
    canvas.width = Math.round(W * scale);
    canvas.height = Math.round(H * scale);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.uniform2f(uR, canvas.width, canvas.height);

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
    const start = performance.now() - 40_000;
    let raf = 0;
    const draw = () => {
      gl.uniform1f(uT, (performance.now() - start) / 1000);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };
    const loop = () => {
      if (!document.hidden) draw();
      raf = requestAnimationFrame(loop);
    };
    const update = () => {
      cancelAnimationFrame(raf);
      if (reduce.matches) draw();
      else loop();
    };
    update();
    reduce.addEventListener("change", update);
    return () => {
      cancelAnimationFrame(raf);
      reduce.removeEventListener("change", update);
      gl.deleteProgram(prog);
    };
  }, []);

  return <canvas ref={ref} className="bd-aurora absolute inset-0 size-full" />;
}

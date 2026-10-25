import { seeded } from "@/lib/contributions";

/* Dust motes drifting through the beam (seeded so server and client match). */
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

/**
 * A stage light on the leader: a lime beam from above and a pool of light below the popover.
 * When the hero stacks (below lg), it shrinks to the popover column and drops the lamp and beam
 * (see globals.css), leaving the pool of light and dust behind the popover.
 */
export function HeroBackdrop() {
  return (
    <div className="bd-spot pointer-events-none absolute top-[54%] left-1/2 h-[860px] w-[920px] -translate-x-1/2 -translate-y-1/2 max-lg:top-[-20px] max-lg:h-[640px] max-lg:translate-y-0">
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

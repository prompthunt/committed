"use client";

import { useEffect, useRef, useState } from "react";
import { contributionYear, SQUARE_SCALE } from "@/lib/contributions";

const WEEKS = 64;
const YEAR = contributionYear(WEEKS);

/**
 * Contribution calendar that separates the hero from the feature grid, as wide as the grid.
 * Narrower screens show fewer, most recent weeks so the squares stay near full size.
 * Squares sweep in left to right the first time the strip scrolls into view.
 */
export function ContributionStrip() {
  const ref = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<"static" | "armed" | "lit">("static");

  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    setState("armed");
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setState("lit");
          io.disconnect();
        }
      },
      { threshold: 0.4 },
    );
    io.observe(node);
    return () => io.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      aria-hidden
      data-state={state}
      className="cs-strip mx-auto w-full max-w-[1240px] py-[clamp(48px,9vw,136px)]"
    >
      <div className="cs-grid grid grid-flow-col gap-1">
        {YEAR.flatMap((week, w) =>
          week.map((level, d) => (
            <span
              key={`${w}-${d}`}
              className="cs-cell aspect-square rounded-[4px]"
              style={{ background: SQUARE_SCALE[level], ["--w" as string]: w, ["--d" as string]: d }}
            />
          )),
        )}
      </div>
    </div>
  );
}

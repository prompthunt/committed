"use client";

import { useEffect, useRef, useState } from "react";
import { contributionYear, SQUARE_SCALE } from "@/lib/contributions";

const WEEKS = 96;
const YEAR = contributionYear(WEEKS);

/**
 * Full-bleed contribution calendar that separates the hero from the feature grid.
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
      className="cs-strip relative -mx-[clamp(20px,5vw,72px)] overflow-hidden py-10 [mask-image:linear-gradient(90deg,transparent,#000_14%,#000_86%,transparent)]"
    >
      <div className="mx-auto grid w-max auto-cols-[15px] grid-flow-col grid-rows-[repeat(7,15px)] gap-1">
        {YEAR.flatMap((week, w) =>
          week.map((level, d) => (
            <span
              key={`${w}-${d}`}
              className="cs-cell size-[15px] rounded-[4px]"
              style={{ background: SQUARE_SCALE[level], ["--w" as string]: w, ["--d" as string]: d }}
            />
          )),
        )}
      </div>
    </div>
  );
}

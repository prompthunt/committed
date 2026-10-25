"use client";

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { FRAME_COUNT } from "@/lib/board";

const LoopContext = createContext(0);
const MotionContext = createContext({ paused: false, toggle: () => {} });

/**
 * One shared clock for every animated demo on the page, so the popover, notifications
 * and People window all tell the same story. Reduced-motion users get the final frame, still.
 */
export function LoopProvider({ children, interval = 2800 }: { children: ReactNode; interval?: number }) {
  const [frame, setFrame] = useState(0);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
    let id: number | undefined;
    const update = () => {
      window.clearInterval(id);
      if (reduce.matches) {
        setFrame(FRAME_COUNT - 1);
      } else if (!paused) {
        id = window.setInterval(() => {
          if (!document.hidden) setFrame((f) => f + 1);
        }, interval);
      }
    };
    update();
    reduce.addEventListener("change", update);
    return () => {
      window.clearInterval(id);
      reduce.removeEventListener("change", update);
    };
  }, [interval, paused]);

  return (
    <MotionContext.Provider value={{ paused, toggle: () => setPaused((value) => !value) }}>
      <LoopContext.Provider value={frame}>{children}</LoopContext.Provider>
    </MotionContext.Provider>
  );
}

export const useFrame = () => useContext(LoopContext);

/** Pause every demo together without adding controls to the app mockup itself. */
export function DemoMotionToggle() {
  const { paused, toggle } = useContext(MotionContext);
  const label = paused ? "Play animated demos" : "Pause animated demos";
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={toggle}
      className="absolute -top-2 right-3 grid size-11 place-items-center rounded-full text-muted transition-colors hover:text-white motion-reduce:hidden"
    >
      <svg aria-hidden width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
        {paused ? <path d="m8 5 11 7-11 7z" /> : <path d="M6 5h4v14H6zm8 0h4v14h-4z" />}
      </svg>
    </button>
  );
}

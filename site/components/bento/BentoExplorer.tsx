"use client";

import { useCallback, useEffect, useState } from "react";
import { FeatureGrid } from "../FeatureGrid";
import { Floodlit } from "./Floodlit";
import { Scoreboard } from "./Scoreboard";
import { Editorial } from "./Editorial";

/*
 * Design exploration: three card treatments for the feature grid, plus the shipped grid.
 * The switcher (bottom of the page, keys 1–3 and 0, or ?bento=<id>) flips between them.
 * Once one is picked, keep that variant, delete the rest, this file, and the switcher.
 */

const VARIANTS = [
  { id: "floodlit", label: "Floodlit", key: "1" },
  { id: "scoreboard", label: "Scoreboard", key: "2" },
  { id: "editorial", label: "Editorial", key: "3" },
  { id: "current", label: "Current", key: "0" },
] as const;

type VariantId = (typeof VARIANTS)[number]["id"];
const isVariant = (v: string | null): v is VariantId => VARIANTS.some((x) => x.id === v);

export function BentoExplorer() {
  const [variant, setVariant] = useState<VariantId>("floodlit");

  useEffect(() => {
    const fromUrl = new URLSearchParams(window.location.search).get("bento");
    if (isVariant(fromUrl)) setVariant(fromUrl);
  }, []);

  const choose = useCallback((id: VariantId) => {
    setVariant(id);
    const url = new URL(window.location.href);
    url.searchParams.set("bento", id);
    window.history.replaceState(null, "", url);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const v = VARIANTS.find((x) => x.key === e.key);
      if (v) choose(v.id);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [choose]);

  return (
    <>
      {variant === "floodlit" && <Floodlit />}
      {variant === "scoreboard" && <Scoreboard />}
      {variant === "editorial" && <Editorial />}
      {variant === "current" && <FeatureGrid />}
      <div className="fixed bottom-5 left-1/2 z-50 flex -translate-x-1/2 items-center gap-1 rounded-full border border-white/10 bg-[#0b0d08]/85 p-1 pl-4 text-[13px] shadow-[0_20px_60px_-20px_#000] backdrop-blur-xl max-sm:pl-1">
        <span className="mr-2 text-muted max-sm:hidden">Cards</span>
        {VARIANTS.map((v) => (
          <button
            key={v.id}
            type="button"
            onClick={() => choose(v.id)}
            aria-pressed={variant === v.id}
            className={`flex h-9 items-center gap-1.5 rounded-full px-3.5 font-medium transition-colors max-sm:px-2.5 ${
              variant === v.id ? "bg-lime text-ink" : "text-soft hover:bg-white/[.07] hover:text-white"
            }`}
          >
            <span className={`text-[11px] tabular-nums max-sm:hidden ${variant === v.id ? "text-ink/55" : "text-faint"}`}>{v.key}</span>
            {v.label}
          </button>
        ))}
      </div>
    </>
  );
}

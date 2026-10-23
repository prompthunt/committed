import type { CSSProperties } from "react";
import { GLYPH_PATH } from "@/lib/glyph";

/** The Committed mark: the GitHub-cat trophy. Colored by `currentColor`. */
export function Glyph({ className, style, title }: { className?: string; style?: CSSProperties; title?: string }) {
  return (
    <svg
      viewBox="0 0 16 16"
      fill="currentColor"
      className={className}
      style={style}
      role={title ? "img" : undefined}
      aria-label={title}
      aria-hidden={title ? undefined : true}
    >
      <path d={GLYPH_PATH} />
    </svg>
  );
}

/** App icon tile: lime trophy on a black squircle. */
export function AppIcon({ size = 96 }: { size?: number }) {
  return (
    <div
      role="img"
      aria-label="Committed app icon"
      className="flex shrink-0 items-center justify-center bg-gradient-to-b from-[#1c1e1c] to-[#070807] shadow-[inset_0_1px_0_rgba(255,255,255,.16),inset_0_0_0_1px_rgba(255,255,255,.07),0_18px_50px_-16px_rgba(200,255,46,.35)]"
      style={{ width: size, height: size, borderRadius: size * 0.23 }}
    >
      <Glyph
        className="text-lime drop-shadow-[0_0_14px_rgba(200,255,46,.45)]"
        style={{ width: size * 0.62, height: size * 0.62 }}
      />
    </div>
  );
}

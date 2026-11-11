import { GLYPH_PATH } from "@/lib/glyph";
import { ageText, passLine, STALE_AFTER_SECONDS, WINDOW_LABELS, type BoardState, type KrakenWindow } from "@/lib/kraken";

export type Shape = "circle" | "square";

interface Props {
  size: number;
  shape: Shape;
  window: KrakenWindow;
  state: BoardState | null;
  /** Shown in place of the rank when there's nothing to rank yet. */
  message?: string | null;
  /** Unix seconds, for the age line. */
  now: number;
}

const GRID = 13;

/** A fixed field of contribution squares, lit like the iPhone app's backdrop. */
const FIELD = (() => {
  let seed = 7;
  const next = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  return Array.from({ length: GRID * GRID }, () => {
    const roll = next();
    return roll > 0.86 ? 3 : roll > 0.66 ? 2 : roll > 0.4 ? 1 : 0;
  });
})();
const SQUARE_COLORS = ["var(--color-sq-0)", "var(--color-sq-1)", "var(--color-sq-2)", "var(--color-sq-3)"];

/** The LCD face: your rank on your Committed board, sized for 240, 320 and 640 px screens. */
export function KrakenFace({ size, shape, window, state, message, now }: Props) {
  const px = (fraction: number, min = 0) => Math.max(Math.round(size * fraction), min);
  const stale = state !== null && now - state.updatedAt > STALE_AFTER_SECONDS;
  const ranked = state !== null && state.rank !== null && !message;
  const empty =
    message ??
    (state === null
      ? "Loading your rank"
      : state.competitorCount <= 1
        ? "Just you so far"
        : state.contributions === null
          ? "Waiting for your first count"
          : null);
  const pass = state && state.rank === 1 ? "You’re in first" : state ? passLine(state) : null;
  const accent = stale ? "var(--color-muted)" : "var(--color-lime)";
  const cell = size / GRID;

  return (
    <div
      role="img"
      aria-label={
        ranked ? `Rank ${state!.rank} of ${state!.competitorCount}, ${state!.contributions} contributions` : (empty ?? "")
      }
      className="relative overflow-hidden bg-ink font-display text-white"
      style={{ width: size, height: size, borderRadius: shape === "circle" ? "50%" : 0 }}
    >
      <svg
        aria-hidden
        width={size}
        height={size}
        className="absolute inset-0"
        style={{
          opacity: stale ? 0.25 : 0.6,
          filter: stale ? "grayscale(1)" : undefined,
          maskImage: "radial-gradient(circle at 50% 50%, transparent 36%, black 82%)",
          WebkitMaskImage: "radial-gradient(circle at 50% 50%, transparent 36%, black 82%)",
        }}
      >
        {FIELD.map((level, i) => (
          <rect
            key={i}
            x={(i % GRID) * cell + cell * 0.12}
            y={Math.floor(i / GRID) * cell + cell * 0.12}
            width={cell * 0.76}
            height={cell * 0.76}
            rx={cell * 0.14}
            fill={SQUARE_COLORS[level]}
          />
        ))}
      </svg>

      <div className="absolute inset-0 flex flex-col items-center justify-center text-center" style={{ gap: px(0.012) }}>
        <div className="flex items-center" style={{ gap: px(0.018), color: accent }}>
          <svg aria-hidden viewBox="0 0 16 16" width={px(0.065, 12)} height={px(0.065, 12)} fill="currentColor">
            <path d={GLYPH_PATH} />
          </svg>
          <span className="font-semibold uppercase" style={{ fontSize: px(0.045, 10), letterSpacing: "0.08em" }}>
            {WINDOW_LABELS[window]}
          </span>
        </div>

        {ranked ? (
          <>
            <div className="font-extrabold tabular-nums" style={{ color: accent, fontSize: px(0.3), lineHeight: 0.95, letterSpacing: "-0.04em" }}>
              #{state!.rank}
            </div>
            <div className="text-muted" style={{ fontSize: px(0.048, 10) }}>
              of {state!.competitorCount}
            </div>
            <div className="flex items-baseline" style={{ gap: px(0.016), marginTop: px(0.02) }}>
              <span className="font-extrabold tabular-nums" style={{ fontSize: px(0.085, 14) }}>
                {state!.contributions!.toLocaleString("en-US")}
              </span>
              <span className="text-soft" style={{ fontSize: px(0.045, 10) }}>
                contributions
              </span>
            </div>
            {pass && (
              <div className="truncate text-soft" style={{ fontSize: px(0.042, 10), maxWidth: size * 0.66 }}>
                {pass}
              </div>
            )}
          </>
        ) : (
          <div className="font-semibold text-soft" style={{ fontSize: px(0.06, 12), maxWidth: size * 0.62, marginTop: px(0.03) }}>
            {empty}
          </div>
        )}

        {state && (
          <div className="text-faint" style={{ fontSize: px(0.034, 9), marginTop: px(0.02) }}>
            Updated {ageText(Math.max(0, now - state.updatedAt))}
          </div>
        )}
      </div>
    </div>
  );
}

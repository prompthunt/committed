"use client";

import type { CSSProperties } from "react";
import { Icon } from "../FeatureGrid";
import { NotificationStack, RankPill } from "../MacUI";
import { useFrame, useMotionPaused } from "../useLoop";
import { avatar, board, FRAME_COUNT, fmt, PEOPLE, SOURCE_URL } from "@/lib/board";
import {
  COMMITS,
  ConnectSheet,
  PERIOD_DESCRIPTIONS,
  PERIODS,
  PIXEL_COMMAND,
  PIXEL_LOCK,
  pixelText,
  rankHistory,
  usePeriod,
} from "./shared";
import grid from "./grid.module.css";
import s from "./Scoreboard.module.css";

/*
 * Option 2 · Scoreboard — the competition, played out. Dot-matrix numerals built from
 * contribution squares, a live podium, a split-flap counter and a bump chart of lead changes.
 */

const vars = (v: Record<string, string | number>) => v as CSSProperties;

/** A dot-matrix sign: every lit pixel is a contribution square. */
function Pixels({ rows, className = "" }: { rows: string[]; className?: string }) {
  return (
    <span aria-hidden className={`${s.pixels} ${className}`} style={vars({ "--cols": rows[0].length })}>
      {rows.flatMap((row, y) =>
        [...row].map((c, x) => <i key={`${x}-${y}`} data-on={c === "#" || undefined} style={vars({ "--x": x, "--y": y })} />),
      )}
    </span>
  );
}

function Marquee({ items, className }: { items: string[]; className: string }) {
  const run = items.map((t, i) => <span key={i}>{t}</span>);
  return (
    <div aria-hidden className={className}>
      <div className={s.marqueeTrack}>
        <div>{run}</div>
        <div>{run}</div>
      </div>
    </div>
  );
}

const SLOT = { 1: { x: 100, h: 112 }, 2: { x: 0, h: 80 }, 3: { x: 200, h: 56 } } as const;

function Podium() {
  const { rows } = board(useFrame());
  const top = rows.filter((r) => r.rank <= 3);
  return (
    <div aria-hidden className={s.podium}>
      {top.map((r) => {
        const slot = SLOT[r.rank as 1 | 2 | 3];
        return (
          <div
            key={r.handle}
            className={`${s.athlete} ${r.rank === 1 ? s.gold : ""}`}
            style={{ transform: `translate(${slot.x}px, ${-slot.h}px)` }}
          >
            <span className={s.athleteCount}>{fmt(r.count)}</span>
            <img src={avatar(r.handle)} alt="" />
            <span className={s.athleteName}>{r.handle}</span>
          </div>
        );
      })}
      {([2, 1, 3] as const).map((rank) => (
        <span key={rank} className={`${s.step} ${rank === 1 ? s.stepGold : ""}`} style={{ left: SLOT[rank].x, height: SLOT[rank].h }}>
          {rank}
        </span>
      ))}
    </div>
  );
}

function SplitFlap({ value }: { value: number }) {
  const digits = String(value).padStart(4, "0").split("");
  return (
    <span aria-hidden className={s.flaps}>
      {digits.map((d, i) => (
        <span key={i} className={s.flap}>
          <span key={`${d}-${value}`} className={s.flapDigit} style={vars({ "--i": i })}>{d}</span>
        </span>
      ))}
    </span>
  );
}

function TimeFrame() {
  const { selected, setSelected, total } = usePeriod();
  return (
    <div className={s.timeDemo}>
      <SplitFlap value={total} />
      <span aria-hidden className={s.flapLabel}>Contributions</span>
      <div role="group" aria-label="Demo contribution time frame" className={s.segments}>
        {PERIODS.map((period, index) => (
          <button key={period} type="button" aria-pressed={selected === index} onClick={() => setSelected(index)}>{period}</button>
        ))}
      </div>
      <span className="sr-only" aria-live="polite">{PERIOD_DESCRIPTIONS[selected]}: {fmt(total)} contributions in this illustrative demo.</span>
    </div>
  );
}

const HISTORY = rankHistory();
const px = (k: number) => 26 + k * 70;
const py = (rank: number) => 22 + (rank - 1) * 40;

/** Rank lines for the three leaders, drawn one lead change at a time. */
function BumpChart() {
  const step = ((useFrame() % FRAME_COUNT) + FRAME_COUNT) % FRAME_COUNT;
  return (
    <svg aria-hidden viewBox="0 0 250 124" className={s.bump}>
      <defs>
        <clipPath id="sb-avatar"><circle r="11" /></clipPath>
      </defs>
      {[1, 2, 3].map((rank) => (
        <g key={rank}>
          <line x1="14" x2="242" y1={py(rank)} y2={py(rank)} className={s.bumpRule} />
          <text x="0" y={py(rank) + 4} className={s.bumpRank}>{rank}</text>
        </g>
      ))}
      {HISTORY.map((line) => (
        <g key={line.handle} className={line.you ? s.bumpYou : s.bumpThem}>
          {line.ranks.slice(1).map((rank, k) => (
            <line
              key={k}
              x1={px(k)} y1={py(line.ranks[k])} x2={px(k + 1)} y2={py(rank)}
              pathLength={1}
              className={s.bumpSeg}
              style={{ strokeDashoffset: k < step ? 0 : 1 }}
            />
          ))}
          <g className={s.bumpHead} style={{ transform: `translate(${px(step)}px, ${py(line.ranks[step])}px)` }}>
            <circle r="13" className={s.bumpRing} />
            <image href={avatar(line.handle)} x="-11" y="-11" width="22" height="22" clipPath="url(#sb-avatar)" />
          </g>
        </g>
      ))}
    </svg>
  );
}

export function Scoreboard() {
  const { youRank } = board(useFrame());
  const paused = useMotionPaused();
  const joiners = PEOPLE.filter((p) => !p.you).map((p) => `+ ${p.handle}`);
  return (
    <section aria-label="Features" className={`${grid.section} ${s.root}`} data-paused={paused || undefined}>
      <div className={grid.grid}>
        <article className={`${s.card} ${s.connect} ${grid.connect}`}>
          <h2>Just connect<br />GitHub.</h2>
          <p>People you follow and members of your GitHub organizations appear automatically.</p>
          <div className={s.connectStage}>
            <Marquee items={joiners} className={`${s.band} ${s.bandA}`} />
            <Marquee items={["Following", "Organizations", "Following", "Organizations"]} className={`${s.band} ${s.bandB}`} />
            <ConnectSheet className={s.sheet} />
          </div>
        </article>

        <article className={`${s.card} ${s.people} ${grid.people}`}>
          <h2>Friends &amp;<br />teammates.</h2>
          <Podium />
          <span className="sr-only">Compare GitHub contribution counts with friends and teammates.</span>
        </article>

        <article className={`${s.card} ${s.small} ${grid.privacy}`}>
          <Pixels rows={PIXEL_LOCK} className={s.sign} />
          <h2>Code stays<br />private.</h2>
          <span className="sr-only">Committed reads contribution counts, never your code. Private contributions count when you enable their visibility on GitHub.</span>
        </article>

        <article className={`${s.card} ${s.small} ${grid.menu}`}>
          <Pixels key={youRank} rows={pixelText(`#${youRank}`)} className={`${s.sign} ${s.rankSign}`} />
          <h2>Menu-bar<br />rank.</h2>
          <span className="sr-only">Your rank, currently #{youRank} in the demo, stays in the menu bar.</span>
        </article>

        <article className={`${s.card} ${s.small} ${grid.source}`}>
          <a href={SOURCE_URL} aria-label="View Committed source on GitHub" className={s.sourceLink}>
            <Marquee items={COMMITS.map(([sha, msg]) => `${sha} ${msg}`)} className={s.ticker} />
            <h2>Open<br />source.</h2>
          </a>
        </article>

        <article className={`${s.card} ${s.time} ${grid.time}`}>
          <h2>Pick a<br />time frame.</h2>
          <TimeFrame />
        </article>

        <article className={`${s.card} ${s.alerts} ${grid.alerts}`}>
          <div aria-hidden className={s.menuBar}>
            <span className={s.live}>Live</span>
            <RankPill rank={youRank} />
            <Icon><path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" /><circle cx="12" cy="19" r=".6" fill="currentColor" /></Icon>
            <Icon><rect x="2" y="6" width="18" height="12" rx="2" /><path d="M23 10v4M6 9v6m4-6v6m4-6v6" /></Icon>
            <span>Wed 4:12 PM</span>
          </div>
          <div className={s.alertBody}>
            <BumpChart />
            <div aria-hidden className={s.notifications}><NotificationStack /></div>
            <div className={s.alertCaption}>
              <h2>Know when you<br />pass each other.</h2>
              <p>Get an alert when you pass a friend or they pass you.</p>
            </div>
          </div>
        </article>

        <article className={`${s.card} ${s.small} ${grid.mac}`}>
          <Pixels rows={PIXEL_COMMAND} className={s.sign} />
          <h2>Built for<br />macOS.</h2>
        </article>
      </div>
    </section>
  );
}

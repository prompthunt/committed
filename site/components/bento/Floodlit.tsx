"use client";

import type { CSSProperties, PointerEvent } from "react";
import { AppIcon, Glyph } from "../Glyph";
import { Icon } from "../FeatureGrid";
import { NotificationStack, RankPill } from "../MacUI";
import { useFrame, useMotionPaused } from "../useLoop";
import { avatar, board, fmt, PEOPLE, SOURCE_URL } from "@/lib/board";
import { ConnectSheet, DAILY, dayLevel, PERIOD_DESCRIPTIONS, PERIODS, usePeriod } from "./shared";
import grid from "./grid.module.css";
import s from "./Floodlit.module.css";

/*
 * Option 1 · Floodlit — the hero's spotlight carried into every tile. Each card is a dark
 * stage with its own light source, film grain and a rim that catches the pointer.
 */

const vars = (v: Record<string, string | number>) => v as CSSProperties;
const LEVEL = ["var(--color-sq-0)", "var(--color-sq-1)", "var(--color-sq-2)", "var(--color-sq-3)", "var(--color-lime)"];

/** Move each card's rim light to the pointer (fine pointers only; purely decorative). */
function trackPointer(e: PointerEvent<HTMLDivElement>) {
  if (e.pointerType !== "mouse") return;
  const card = (e.target as HTMLElement).closest<HTMLElement>("[data-card]");
  if (!card) return;
  const r = card.getBoundingClientRect();
  card.style.setProperty("--mx", `${e.clientX - r.left}px`);
  card.style.setProperty("--my", `${e.clientY - r.top}px`);
}

function Orbit() {
  const others = PEOPLE.filter((p) => !p.you);
  return (
    <div aria-hidden className={s.orbit}>
      <div className={s.ring}>
        {others.map((p, i) => (
          <span key={p.handle} className={s.satellite} style={vars({ "--a": `${(i * 360) / others.length + 20}deg` })}>
            <img src={avatar(p.handle)} alt="" />
          </span>
        ))}
      </div>
    </div>
  );
}

function Gauges() {
  const { rows } = board(useFrame());
  const max = Math.max(...rows.map((r) => r.count));
  const C = 2 * Math.PI * 29;
  return (
    <div aria-hidden className={s.gauges}>
      {rows.map((r) => (
        <div key={r.handle} className={`${s.gauge} ${r.rank === 1 ? s.leader : ""} ${r.you ? s.gaugeYou : ""}`}>
          <span className={s.dial}>
            <svg viewBox="0 0 64 64">
              <circle cx="32" cy="32" r="29" className={s.track} />
              <circle cx="32" cy="32" r="29" className={s.arc} strokeDasharray={C} strokeDashoffset={C * (1 - r.count / max)} />
            </svg>
            <img src={avatar(r.handle)} alt="" />
            {r.rank === 1 && <span className={s.crown}><Glyph /></span>}
          </span>
          <span className={s.gaugeName}>{r.handle}</span>
          <span className={s.gaugeCount}>{fmt(r.count)}</span>
        </div>
      ))}
    </div>
  );
}

function Redacted() {
  const lines = [[38, 22, 30], [16, 46], [16, 28, 34], [52], [26, 40]];
  return (
    <div aria-hidden className={s.redacted}>
      <div className={s.code}>
        {lines.map((line, i) => (
          <span key={i} className={s.codeLine}>
            {line.map((w, j) => <i key={j} style={{ width: `${w}%` }} />)}
          </span>
        ))}
      </div>
      <span className={s.lock}><Icon><rect x="5" y="10.5" width="14" height="10" rx="2.2" /><path d="M8.5 10.5V7.5a3.5 3.5 0 0 1 7 0v3" /></Icon></span>
    </div>
  );
}

function MenuStrip() {
  const { youRank } = board(useFrame());
  return (
    <div aria-hidden className={s.menuStrip}>
      <span className={s.menuBeam} />
      <span className={s.menuItems}>
        <Icon><circle cx="11" cy="11" r="6" /><path d="m20 20-4.5-4.5" /></Icon>
        <RankPill rank={youRank} className={s.menuPill} />
        <Icon><path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" /><circle cx="12" cy="19" r=".6" fill="currentColor" /></Icon>
        <span>4:12</span>
      </span>
    </div>
  );
}

function CommitGraph() {
  return (
    <svg aria-hidden viewBox="0 0 150 54" className={s.graph}>
      <path d="M6 38H144" className={s.graphMain} />
      <path d="M44 38C58 38 58 14 74 14H96C112 14 112 38 126 38" className={s.graphBranch} />
      {[6, 26, 44, 86, 144].map((x) => <circle key={x} cx={x} cy="38" r="4" className={s.node} />)}
      {[74, 96].map((x) => <circle key={x} cx={x} cy="14" r="4" className={s.nodeBranch} />)}
      <circle cx="126" cy="38" r="5.5" className={s.head} />
    </svg>
  );
}

function TimeFrame() {
  const { selected, setSelected, total, days } = usePeriod();
  return (
    <div className={s.timeDemo}>
      <div role="group" aria-label="Demo contribution time frame" className={s.segments}>
        {PERIODS.map((period, index) => (
          <button key={period} type="button" aria-pressed={selected === index} onClick={() => setSelected(index)}>{period}</button>
        ))}
      </div>
      <div aria-hidden className={s.calendar}>
        {DAILY.map((n, i) => {
          const on = i >= DAILY.length - days;
          return (
            <i
              key={i}
              data-on={on || undefined}
              style={vars({ "--c": LEVEL[Math.max(2, dayLevel(n))], "--i": DAILY.length - 1 - i })}
            />
          );
        })}
      </div>
      <div aria-hidden className={s.timeTotal}>
        <span>{fmt(total)}</span>
        <small>contributions</small>
      </div>
      <span className="sr-only" aria-live="polite">{PERIOD_DESCRIPTIONS[selected]}: {fmt(total)} contributions in this illustrative demo.</span>
    </div>
  );
}

export function Floodlit() {
  const { youRank } = board(useFrame());
  const paused = useMotionPaused();
  return (
    <section aria-label="Features" className={`${grid.section} ${s.root}`} data-paused={paused || undefined}>
      <div className={grid.grid} onPointerMove={trackPointer}>
        <article data-card className={`${s.card} ${s.connect} ${grid.connect}`}>
          <span aria-hidden className={s.connectSquares} />
          <h2>Just connect<br />GitHub.</h2>
          <p>People you follow and members of your GitHub organizations appear automatically.</p>
          <div className={s.connectStage}>
            <Orbit />
            <ConnectSheet className={s.sheet} />
          </div>
        </article>

        <article data-card className={`${s.card} ${s.people} ${grid.people}`} style={vars({ "--ly": "0%" })}>
          <h2>Friends &amp;<br />teammates.</h2>
          <Gauges />
          <span className="sr-only">Compare GitHub contribution counts with friends and teammates.</span>
        </article>

        <article data-card className={`${s.card} ${s.small} ${grid.privacy}`} style={vars({ "--lx": "50%", "--ly": "30%" })}>
          <Redacted />
          <h2>Code stays<br />private.</h2>
          <span className="sr-only">Committed reads contribution counts, never your code. Private contributions count when you enable their visibility on GitHub.</span>
        </article>

        <article data-card className={`${s.card} ${s.small} ${grid.menu}`} style={vars({ "--ly": "-30%", "--la": ".12" })}>
          <MenuStrip />
          <h2>Menu-bar<br />rank.</h2>
          <span className="sr-only">Your rank, currently #{youRank} in the demo, stays in the menu bar.</span>
        </article>

        <article data-card className={`${s.card} ${s.small} ${grid.source}`} style={vars({ "--lx": "80%", "--ly": "20%" })}>
          <a href={SOURCE_URL} aria-label="View Committed source on GitHub" className={s.sourceLink}>
            <CommitGraph />
            <h2>Open<br />source.</h2>
            <span aria-hidden className={s.repo}>prompthunt/committed ↗</span>
          </a>
        </article>

        <article data-card className={`${s.card} ${s.time} ${grid.time}`} style={vars({ "--ly": "100%" })}>
          <h2>Pick a<br />time frame.</h2>
          <TimeFrame />
        </article>

        <article data-card className={`${s.card} ${s.alerts} ${grid.alerts}`}>
          <div aria-hidden className={s.wallpaper}><i /><i /><i /></div>
          <div aria-hidden className={s.desktopScene}>
            <div className={s.menuBar}>
              <RankPill rank={youRank} />
              <Icon><path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" /><circle cx="12" cy="19" r=".6" fill="currentColor" /></Icon>
              <Icon><rect x="2" y="6" width="18" height="12" rx="2" /><path d="M23 10v4M6 9v6m4-6v6m4-6v6" /></Icon>
              <span>Wed 4:12 PM</span>
            </div>
            <div className={s.notifications}><NotificationStack /></div>
          </div>
          <div className={s.alertCaption}>
            <h2>Know when you<br />pass each other.</h2>
            <p>Get an alert when you pass a friend or they pass you.</p>
          </div>
        </article>

        <article data-card className={`${s.card} ${s.small} ${grid.mac}`} style={vars({ "--ly": "-20%", "--la": ".1" })}>
          <div aria-hidden className={s.pedestal}>
            <span className={s.pedestalBeam} />
            <AppIcon size={60} />
            <span className={s.reflection}><AppIcon size={60} /></span>
          </div>
          <h2>Built for<br />macOS.</h2>
        </article>
      </div>
    </section>
  );
}

"use client";

import { useState, type CSSProperties, type ReactNode } from "react";
import { NotificationStack, RankPill } from "./MacUI";
import { useFrame } from "./useLoop";
import { avatar, board, DAILY, fmt, SOURCE_URL, WINDOW_COUNTS } from "@/lib/board";
import { SQUARE_SCALE } from "@/lib/contributions";
import styles from "./FeatureGrid.module.css";

/*
 * The feature grid, set like a printed spread: indexed, left-aligned cards in paper, lime
 * and ink, oversized type, and product crops that bleed off the edge.
 */

const vars = (v: Record<string, string | number>) => v as CSSProperties;

function Icon({ children }: { children: ReactNode }) {
  return <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{children}</svg>;
}

function GitHubMark({ className }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 16 16" fill="currentColor" className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

/** A small index and label above each card, like a folio line. */
function Meta({ n, label }: { n: string; label: string }) {
  return (
    <div aria-hidden className={styles.meta}>
      <span>{n}</span>
      <span>{label}</span>
    </div>
  );
}

/** A decorative crop of the app's first-run connection screen. */
function ConnectSheet() {
  return (
    <div aria-hidden className={styles.sheet}>
      <GitHubMark className={styles.sheetMark} />
      <strong>Committed</strong>
      <span className={styles.sheetButton}><GitHubMark />Connect GitHub</span>
      <span className={styles.sheetFoot}>Committed never sees your code.</span>
    </div>
  );
}

/** The leaderboard as a results table; rows slide as the shared loop changes ranks. */
function Results() {
  const { rows } = board(useFrame());
  const ROW = 38;
  return (
    <ol aria-hidden className={styles.results} style={{ height: 5 * ROW }}>
      {rows.map((r) => (
        <li
          key={r.handle}
          className={`${r.you ? styles.resultYou : ""} ${r.rank > 5 ? styles.resultOut : ""}`}
          style={{ transform: `translateY(${(Math.min(r.rank, 6) - 1) * ROW}px)` }}
        >
          <span className={styles.resultRank}>{String(r.rank).padStart(2, "0")}</span>
          <img src={avatar(r.handle)} alt="" />
          <span className={styles.resultName}>{r.handle}</span>
          <span className={styles.resultCount}>{fmt(r.count)}</span>
        </li>
      ))}
    </ol>
  );
}

const PERIODS = ["Today", "7 days", "30 days"];
const PERIOD_DESCRIPTIONS = ["Today", "Past 7 days", "Past 30 days"];
const PERIOD_DAYS = [1, 7, 30];

/** Contribution-square shade (1–4) for a day, relative to the busiest day in the window. */
const BUSIEST = Math.max(...DAILY);
const squareLevel = (n: number) => {
  const f = n / BUSIEST;
  return f < 0.28 ? 1 : f < 0.5 ? 2 : f < 0.75 ? 3 : 4;
};

function TimeFrame() {
  const [selected, setSelected] = useState(0);
  const total = WINDOW_COUNTS[selected];
  return (
    <div className={styles.timeDemo}>
      <div aria-hidden className={styles.timeFigure}>
        <span key={total} className={styles.timeTotal}>{fmt(total)}</span>
        <span className={styles.timeUnit}>contributions</span>
      </div>
      <div aria-hidden className={styles.squares}>
        {DAILY.map((n, i) => (
          <i
            key={i}
            data-on={i >= DAILY.length - PERIOD_DAYS[selected] || undefined}
            style={vars({ "--c": SQUARE_SCALE[squareLevel(n)], "--i": DAILY.length - 1 - i })}
          />
        ))}
      </div>
      <div role="group" aria-label="Demo contribution time frame" className={styles.tabs}>
        {PERIODS.map((period, index) => (
          <button key={period} type="button" aria-pressed={selected === index} onClick={() => setSelected(index)}>{period}</button>
        ))}
      </div>
      <span className="sr-only" aria-live="polite">{PERIOD_DESCRIPTIONS[selected]}: {fmt(total)} contributions in this illustrative demo.</span>
    </div>
  );
}

export function FeatureGrid() {
  const { youRank } = board(useFrame());
  return (
    <section aria-label="Features" className={styles.section}>
      <div className={styles.grid}>
        <article className={`${styles.card} ${styles.lime} ${styles.connect}`}>
          <Meta n="01" label="Setup" />
          <div className={styles.connectCopy}>
            <h2>Just connect<br />GitHub.</h2>
            <p>People you follow and members of your GitHub organizations appear automatically.</p>
          </div>
          <div aria-hidden className={styles.connectCrop}><ConnectSheet /></div>
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.people}`}>
          <Meta n="02" label="People" />
          <Results />
          <h2>Friends &amp;<br />teammates.</h2>
          <span className="sr-only">Compare GitHub contribution counts with friends and teammates.</span>
        </article>

        <article className={`${styles.card} ${styles.paper} ${styles.small} ${styles.privacy}`}>
          <Meta n="03" label="Privacy" />
          <div aria-hidden className={styles.redacted}>
            <span>git diff <b>████████</b></span>
            <span>+ <b>██████</b> <b>████</b></span>
            <span>contributions <em>223</em></span>
          </div>
          <h2>Code stays<br />private.</h2>
          <span className="sr-only">Committed reads contribution counts, never your code. Private contributions count when you enable their visibility on GitHub.</span>
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.small} ${styles.menu}`}>
          <Meta n="04" label="Menu bar" />
          <div aria-hidden className={styles.numeral}>
            <span key={youRank}><i>#</i>{youRank}</span>
            <RankPill rank={youRank} className={styles.numeralPill} />
          </div>
          <h2>Menu-bar<br />rank.</h2>
          <span className="sr-only">Your rank, currently #{youRank} in the demo, stays in the menu bar.</span>
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.small} ${styles.source}`}>
          <a href={SOURCE_URL} aria-label="View Committed source on GitHub" className={styles.sourceLink}>
            <Meta n="05" label="Source" />
            <span aria-hidden className={styles.repo}>prompthunt/<br />committed<span className={styles.arrow}>↗</span></span>
            <h2>Open<br />source.</h2>
          </a>
        </article>

        <article className={`${styles.card} ${styles.paper} ${styles.time}`}>
          <Meta n="06" label="Range" />
          <h2>Pick a<br />time frame.</h2>
          <TimeFrame />
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.alerts}`}>
          <div aria-hidden className={styles.desktopScene}>
            <div className={styles.menuBar}>
              <RankPill rank={youRank} />
              <Icon><path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" /><circle cx="12" cy="19" r=".6" fill="currentColor" /></Icon>
              <Icon><rect x="2" y="6" width="18" height="12" rx="2" /><path d="M23 10v4M6 9v6m4-6v6m4-6v6" /></Icon>
              <span>Wed 4:12 PM</span>
            </div>
            <div className={styles.notifications}><NotificationStack /></div>
          </div>
          <div className={styles.alertCaption}>
            <Meta n="07" label="Alerts" />
            <div className={styles.alertCopy}>
              <h2>Know when you<br />pass each other.</h2>
              <p>Get an alert when you pass a friend or they pass you.</p>
            </div>
          </div>
        </article>

        <article className={`${styles.card} ${styles.lime} ${styles.small} ${styles.mac}`}>
          <Meta n="08" label="macOS 26+" />
          <span aria-hidden className={styles.command}>⌘</span>
          <h2>Built for<br />macOS.</h2>
        </article>
      </div>
    </section>
  );
}

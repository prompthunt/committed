"use client";

import { useState, type ReactNode } from "react";
import {
  ConnectScreen,
  GitHubMark,
  NotificationStack,
  PeopleWindow,
  RankPill,
  WindowPicker,
  YouSummary,
} from "./MacUI";
import { Glyph } from "./Glyph";
import { useFrame } from "./useLoop";
import { board, fmt, SOURCE_URL, WINDOW_COUNTS } from "@/lib/board";
import styles from "./FeatureGrid.module.css";

/*
 * The feature grid, set like a printed spread: indexed, left-aligned cards in paper, lime
 * and ink, oversized type, and crops of the app's real screens that bleed off the edge.
 */

function Icon({ children }: { children: ReactNode }) {
  return <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{children}</svg>;
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

/** The compact cards each show a single mark instead of a crop. */
function LockMark() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" className={styles.mark}>
      <rect x="4.5" y="10.5" width="15" height="10.5" rx="2.5" />
      <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
      <path d="M12 14.5v2.5" />
    </svg>
  );
}

/** A smiling vintage compact Mac in chunky pixels, drawn as an homage rather than Apple's artwork. */
function HappyMac() {
  return (
    <svg aria-hidden viewBox="0 0 14 19" fill="currentColor" shapeRendering="crispEdges" className={`${styles.mark} ${styles.macMark}`}>
      <path d="M1 0h12v1h-12zM0 1h1v1h-1zM13 1h1v1h-1zM0 2h1v1h-1zM2 2h10v1h-10zM13 2h1v1h-1zM0 3h1v1h-1zM2 3h1v1h-1zM11 3h1v1h-1zM13 3h1v1h-1zM0 4h1v1h-1zM2 4h1v1h-1zM5 4h1v1h-1zM8 4h1v1h-1zM11 4h1v1h-1zM13 4h1v1h-1zM0 5h1v1h-1zM2 5h1v1h-1zM5 5h1v1h-1zM8 5h1v1h-1zM11 5h1v1h-1zM13 5h1v1h-1zM0 6h1v1h-1zM2 6h1v1h-1zM7 6h1v1h-1zM11 6h1v1h-1zM13 6h1v1h-1zM0 7h1v1h-1zM2 7h1v1h-1zM6 7h2v1h-2zM11 7h1v1h-1zM13 7h1v1h-1zM0 8h1v1h-1zM2 8h1v1h-1zM11 8h1v1h-1zM13 8h1v1h-1zM0 9h1v1h-1zM2 9h1v1h-1zM4 9h1v1h-1zM9 9h1v1h-1zM11 9h1v1h-1zM13 9h1v1h-1zM0 10h1v1h-1zM2 10h1v1h-1zM5 10h4v1h-4zM11 10h1v1h-1zM13 10h1v1h-1zM0 11h1v1h-1zM2 11h1v1h-1zM11 11h1v1h-1zM13 11h1v1h-1zM0 12h1v1h-1zM2 12h10v1h-10zM13 12h1v1h-1zM0 13h1v1h-1zM13 13h1v1h-1zM0 14h1v1h-1zM8 14h4v1h-4zM13 14h1v1h-1zM0 15h1v1h-1zM13 15h1v1h-1zM0 16h14v1h-14zM2 17h1v1h-1zM11 17h1v1h-1zM2 18h10v1h-10z" />
    </svg>
  );
}

const PERIOD_DESCRIPTIONS = ["Today", "Past 7 days", "Past 30 days"];

/** The popover's real time-frame control and summary card, switchable here. */
function TimeFrame() {
  const [selected, setSelected] = useState(0);
  const total = WINDOW_COUNTS[selected];
  return (
    <div className={styles.timeDemo}>
      <WindowPicker selected={selected} onSelect={setSelected} large />
      <div aria-hidden className={styles.timeSummary}><YouSummary count={total} /></div>
      <span className="sr-only" aria-live="polite">{PERIOD_DESCRIPTIONS[selected]}: {fmt(total)} contributions in this illustrative demo.</span>
    </div>
  );
}

export function FeatureGrid() {
  const { youRank } = board(useFrame());
  return (
    <section aria-labelledby="features-title" className={styles.section}>
      <header className="mb-[clamp(28px,3.5vw,48px)]">
        <p className="font-mono text-[11px] font-medium tracking-[.06em] text-muted uppercase">How it works</p>
        <h2 id="features-title" className="mt-4 max-w-[18ch] text-[clamp(32px,4.4vw,56px)] leading-[0.95] font-[750] tracking-[-0.05em] text-balance">
          A leaderboard of the people you already follow.
        </h2>
      </header>
      <div className={styles.grid}>
        <article className={`${styles.card} ${styles.lime} ${styles.connect}`}>
          <Meta n="01" label="Setup" />
          <div className={styles.connectCopy}>
            <h2>Just connect<br />GitHub.</h2>
            <p>People you follow and members of your GitHub organizations appear automatically.</p>
          </div>
          <div aria-hidden className={styles.connectCrop}><ConnectScreen className={styles.sheet} /></div>
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.people}`}>
          <Meta n="02" label="People" />
          <div aria-hidden className={styles.peopleCrop}><PeopleWindow /></div>
          <h2>Friends &amp;<br />teammates.</h2>
          <span className="sr-only">Compare GitHub contribution counts with friends and teammates.</span>
        </article>

        <article className={`${styles.card} ${styles.paper} ${styles.small} ${styles.privacy}`}>
          <Meta n="03" label="Privacy" />
          <LockMark />
          <h2>Code stays<br />private.</h2>
          <span className="sr-only">Committed reads contribution counts, never your code. Private contributions count when you enable their visibility on GitHub.</span>
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.small} ${styles.menu}`}>
          <Meta n="04" label="Menu bar" />
          <div aria-hidden className={styles.rankMark}><Glyph className={styles.mark} /><span>#{youRank}</span></div>
          <h2>Menu-bar<br />rank.</h2>
          <span className="sr-only">Your rank, currently #{youRank} in the demo, stays in the menu bar.</span>
        </article>

        <article className={`${styles.card} ${styles.ink} ${styles.small} ${styles.source}`}>
          <a href={SOURCE_URL} aria-label="View Committed source on GitHub" className={styles.sourceLink}>
            <Meta n="05" label="Source" />
            <span aria-hidden className={styles.sourceMark}><GitHubMark className={styles.mark} /><span className={styles.arrow}>↗</span></span>
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
          <Meta n="08" label="macOS 26+ · Windows 11" />
          <HappyMac />
          <h2>In your menu bar.<br />Or your tray.</h2>
        </article>
      </div>
    </section>
  );
}

"use client";

import { useState, type ReactNode } from "react";
import { NotificationStack, RankPill } from "./MacUI";
import { useFrame } from "./useLoop";
import { avatar, board, fmt, ME, SOURCE_URL, WINDOW_COUNTS } from "@/lib/board";
import styles from "./FeatureGrid.module.css";

export function Icon({ children }: { children: ReactNode }) {
  return <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{children}</svg>;
}

export function GitHubMark({ className }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 16 16" fill="currentColor" className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

/** A decorative crop of the app's first-run connection screen. */
function ConnectPreview() {
  return (
    <div aria-hidden className={styles.connectPreview}>
      <GitHubMark />
      <strong>Committed</strong>
      <span className={styles.connectButton}><GitHubMark />Connect GitHub</span>
      <span className={styles.connectFoot}>Committed never sees your code.</span>
    </div>
  );
}

function TimeFramePreview() {
  const [selected, setSelected] = useState(0);
  const periods = ["Today", "7 days", "30 days"];
  const descriptions = ["Today", "Past 7 days", "Past 30 days"];
  return (
    <div className={styles.timePreview}>
      <div role="group" aria-label="Demo contribution time frame" className={styles.segments}>
        {periods.map((period, index) => (
          <button key={period} type="button" aria-pressed={selected === index} onClick={() => setSelected(index)}>{period}</button>
        ))}
      </div>
      <div className={styles.summary}>
        <img src={ME.avatar} alt="Addison" />
        <div><span className={styles.total}>{fmt(WINDOW_COUNTS[selected])}</span><span className={styles.countLabel}>contributions</span></div>
      </div>
      <span className="sr-only" aria-live="polite">{descriptions[selected]}: {fmt(WINDOW_COUNTS[selected])} contributions in this illustrative demo.</span>
    </div>
  );
}

export function FeatureGrid() {
  const current = board(useFrame());
  const people = [...current.rows].sort((a, b) => a.rank - b.rank).slice(0, 3);
  return (
    <section aria-label="Features" className={styles.section}>
      <div className={styles.grid}>
        <article className={`${styles.card} ${styles.connect}`}>
          <h2>Just connect<br />GitHub.</h2>
          <p>People you follow and members of your GitHub organizations appear automatically.</p>
          <ConnectPreview />
        </article>

        <article className={`${styles.card} ${styles.people}`}>
          <h2>Friends &amp;<br />teammates.</h2>
          <div aria-hidden className={styles.roster}>
            {people.map(person => (
              <div key={person.handle} className={`${styles.person} ${person.you ? styles.you : ""}`}>
                <img src={avatar(person.handle)} alt="" />
                <span className={styles.handle}>{person.handle}{person.you && <span className={styles.youBadge}>You</span>}</span>
                <span className={styles.score}>{fmt(person.count)}</span>
              </div>
            ))}
          </div>
          <span className="sr-only">Compare GitHub contribution counts with friends and teammates.</span>
        </article>

        <article className={`${styles.card} ${styles.small} ${styles.privacy}`}>
          <span className={styles.icon}><Icon><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V6a4 4 0 0 1 8 0v4" /><circle cx="12" cy="15" r="1" /></Icon></span>
          <h2>Code stays<br />private.</h2>
          <span className="sr-only">Committed reads contribution counts, never your code. Private contributions count when you enable their visibility on GitHub.</span>
        </article>

        <article className={`${styles.card} ${styles.small} ${styles.menu}`}>
          <div aria-hidden className={styles.menuRank}><RankPill rank={current.youRank} /></div>
          <h2>Menu-bar<br />rank.</h2>
        </article>

        <article className={`${styles.card} ${styles.small} ${styles.source}`}>
          <a href={SOURCE_URL} aria-label="View Committed source on GitHub" className={styles.sourceLink}>
            <span className={styles.icon}><Icon><path d="m7 8-4 4 4 4m10-8 4 4-4 4M14 4l-4 16" /></Icon></span>
            <h2>Open<br />source.</h2>
          </a>
        </article>

        <article className={`${styles.card} ${styles.time}`}>
          <h2>Pick a<br />time frame.</h2>
          <TimeFramePreview />
        </article>

        <article className={`${styles.card} ${styles.alerts}`}>
          <div aria-hidden className={styles.desktopScene}>
            <div className={styles.menuBar}>
              <RankPill rank={current.youRank} />
              <Icon><path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" /><circle cx="12" cy="19" r=".6" fill="currentColor" /></Icon>
              <Icon><rect x="2" y="6" width="18" height="12" rx="2" /><path d="M23 10v4M6 9v6m4-6v6m4-6v6" /></Icon>
              <span>Wed 4:12 PM</span>
            </div>
            <div className={styles.notifications}><NotificationStack /></div>
          </div>
          <div className={styles.alertCaption}>
            <h2>Know when you<br />pass each other.</h2>
            <p>Get an alert when you pass a friend or they pass you.</p>
          </div>
        </article>

        <article className={`${styles.card} ${styles.small} ${styles.mac}`}>
          <span className={styles.icon}><Icon><rect x="2" y="3" width="20" height="14" rx="2" /><path d="M12 17v4m-4 0h8" /></Icon></span>
          <h2>Built for<br />macOS.</h2>
        </article>
      </div>
    </section>
  );
}

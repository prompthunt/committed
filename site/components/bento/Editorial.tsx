"use client";

import type { CSSProperties } from "react";
import { Icon } from "../FeatureGrid";
import { NotificationStack, RankPill } from "../MacUI";
import { useFrame } from "../useLoop";
import { avatar, board, fmt, SOURCE_URL } from "@/lib/board";
import { ConnectSheet, DAILY, PERIOD_DESCRIPTIONS, PERIODS, usePeriod } from "./shared";
import grid from "./grid.module.css";
import s from "./Editorial.module.css";

/*
 * Option 3 · Editorial — the grid as a printed spread. Indexed, left-aligned cards in
 * paper, lime and ink; oversized type; product crops that bleed off the edge.
 */

const vars = (v: Record<string, string | number>) => v as CSSProperties;

function Meta({ n, label }: { n: string; label: string }) {
  return (
    <div aria-hidden className={s.meta}>
      <span>{n}</span>
      <span>{label}</span>
    </div>
  );
}

function Results() {
  const { rows } = board(useFrame());
  const ROW = 38;
  return (
    <ol aria-hidden className={s.results} style={{ height: 5 * ROW }}>
      {rows.map((r) => (
        <li
          key={r.handle}
          className={`${r.you ? s.resultYou : ""} ${r.rank > 5 ? s.resultOut : ""}`}
          style={{ transform: `translateY(${(Math.min(r.rank, 6) - 1) * ROW}px)` }}
        >
          <span className={s.resultRank}>{String(r.rank).padStart(2, "0")}</span>
          <img src={avatar(r.handle)} alt="" />
          <span className={s.resultName}>{r.handle}</span>
          <span className={s.resultCount}>{fmt(r.count)}</span>
        </li>
      ))}
    </ol>
  );
}

function TimeFrame() {
  const { selected, setSelected, total, days } = usePeriod();
  const max = Math.max(...DAILY);
  return (
    <div className={s.timeDemo}>
      <div aria-hidden className={s.timeFigure}>
        <span key={total} className={s.timeTotal}>{fmt(total)}</span>
        <span className={s.timeUnit}>contributions</span>
      </div>
      <div aria-hidden className={s.bars}>
        {DAILY.map((n, i) => (
          <i key={i} data-on={i >= DAILY.length - days || undefined} style={vars({ "--h": `${Math.max(6, (n / max) * 100)}%`, "--i": DAILY.length - 1 - i })} />
        ))}
      </div>
      <div role="group" aria-label="Demo contribution time frame" className={s.tabs}>
        {PERIODS.map((period, index) => (
          <button key={period} type="button" aria-pressed={selected === index} onClick={() => setSelected(index)}>{period}</button>
        ))}
      </div>
      <span className="sr-only" aria-live="polite">{PERIOD_DESCRIPTIONS[selected]}: {fmt(total)} contributions in this illustrative demo.</span>
    </div>
  );
}

export function Editorial() {
  const { youRank } = board(useFrame());
  return (
    <section aria-label="Features" className={`${grid.section} ${s.root}`}>
      <div className={grid.grid}>
        <article className={`${s.card} ${s.lime} ${s.connect} ${grid.connect}`}>
          <Meta n="01" label="Setup" />
          <div className={s.connectCopy}>
            <h2>Just connect<br />GitHub.</h2>
            <p>People you follow and members of your GitHub organizations appear automatically.</p>
          </div>
          <div aria-hidden className={s.connectCrop}><ConnectSheet className={s.sheet} /></div>
        </article>

        <article className={`${s.card} ${s.ink} ${s.people} ${grid.people}`}>
          <Meta n="02" label="People" />
          <Results />
          <h2>Friends &amp;<br />teammates.</h2>
          <span className="sr-only">Compare GitHub contribution counts with friends and teammates.</span>
        </article>

        <article className={`${s.card} ${s.paper} ${s.small} ${grid.privacy}`}>
          <Meta n="03" label="Privacy" />
          <div aria-hidden className={s.redacted}>
            <span>git diff <b>████████</b></span>
            <span>+ <b>██████</b> <b>████</b></span>
            <span>contributions <em>223</em></span>
          </div>
          <h2>Code stays<br />private.</h2>
          <span className="sr-only">Committed reads contribution counts, never your code. Private contributions count when you enable their visibility on GitHub.</span>
        </article>

        <article className={`${s.card} ${s.ink} ${s.small} ${grid.menu}`}>
          <Meta n="04" label="Menu bar" />
          <div aria-hidden className={s.numeral}>
            <span key={youRank}><i>#</i>{youRank}</span>
            <RankPill rank={youRank} className={s.numeralPill} />
          </div>
          <h2>Menu-bar<br />rank.</h2>
          <span className="sr-only">Your rank, currently #{youRank} in the demo, stays in the menu bar.</span>
        </article>

        <article className={`${s.card} ${s.ink} ${s.small} ${s.source} ${grid.source}`}>
          <a href={SOURCE_URL} aria-label="View Committed source on GitHub" className={s.sourceLink}>
            <Meta n="05" label="Source" />
            <span aria-hidden className={s.repo}>prompthunt/<br />committed<span className={s.arrow}>↗</span></span>
            <h2>Open<br />source.</h2>
          </a>
        </article>

        <article className={`${s.card} ${s.paper} ${s.time} ${grid.time}`}>
          <Meta n="06" label="Range" />
          <h2>Pick a<br />time frame.</h2>
          <TimeFrame />
        </article>

        <article className={`${s.card} ${s.ink} ${s.alerts} ${grid.alerts}`}>
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
            <Meta n="07" label="Alerts" />
            <div className={s.alertCopy}>
              <h2>Know when you<br />pass each other.</h2>
              <p>Get an alert when you pass a friend or they pass you.</p>
            </div>
          </div>
        </article>

        <article className={`${s.card} ${s.lime} ${s.small} ${s.mac} ${grid.mac}`}>
          <Meta n="08" label="macOS 26+" />
          <span aria-hidden className={s.command}>⌘</span>
          <h2>Built for<br />macOS.</h2>
        </article>
      </div>
    </section>
  );
}

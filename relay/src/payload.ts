// ActivityKit push payloads (Apple: "Starting and updating Live Activities with ActivityKit push
// notifications"). `content-state` must decode as LiveRankAttributes.ContentState with the default
// JSONDecoder, so dates are integer Unix seconds and nil values are omitted, as Swift encodes them.

import type { LiveRankState } from "./ranking";
import type { ContributionWindow } from "./types";

/** A Live Activity is stale 20 minutes after the data it shows. */
export const STALE_AFTER_SECONDS = 20 * 60;

export function staleDate(state: LiveRankState): number {
  return state.updatedAt + STALE_AFTER_SECONDS;
}

export function contentState(state: LiveRankState): Record<string, unknown> {
  return Object.fromEntries(Object.entries(state).filter(([, value]) => value !== null));
}

export function updatePayload(state: LiveRankState, now: number): unknown {
  return {
    aps: {
      timestamp: Math.floor(now),
      event: "update",
      "content-state": contentState(state),
      "stale-date": staleDate(state),
    },
  };
}

/** Ends the activity and removes it at once (a dismissal date in the past). */
export function endPayload(state: LiveRankState, now: number): unknown {
  return {
    aps: {
      timestamp: Math.floor(now),
      event: "end",
      "content-state": contentState(state),
      "dismissal-date": Math.floor(now) - 60,
    },
  };
}

/** Push-to-start. Apple requires an alert and the attributes; `input-push-token` asks iOS 18+ for an update token. */
export function startPayload(selfLogin: string, state: LiveRankState, now: number): unknown {
  return {
    aps: {
      timestamp: Math.floor(now),
      event: "start",
      "content-state": contentState(state),
      "stale-date": staleDate(state),
      "attributes-type": "LiveRankAttributes",
      attributes: { selfLogin },
      "input-push-token": 1,
      alert: { title: "Live rank", body: startBody(state) },
    },
  };
}

const WINDOW_PHRASE: Record<ContributionWindow, string> = {
  daily: "today",
  weekly: "over 7 days",
  monthly: "over 30 days",
};

function startBody(state: LiveRankState): string {
  if (state.rank !== null) return `You're #${state.rank} of ${state.competitorCount} ${WINDOW_PHRASE[state.window]}.`;
  if (state.contributions !== null) {
    return `${state.contributions} ${state.contributions === 1 ? "contribution" : "contributions"} ${WINDOW_PHRASE[state.window]}.`;
  }
  return "Following your rank.";
}

/** The state shown before any data has loaded: placeholders, never zero. */
export function placeholderState(window: ContributionWindow, competitorCount: number, now: number): LiveRankState {
  return {
    window,
    rank: null,
    competitorCount,
    contributions: null,
    above: null,
    below: null,
    movementToday: 0,
    updatedAt: Math.floor(now),
  };
}

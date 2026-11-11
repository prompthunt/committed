"use client";

import { useEffect, useState } from "react";
import { boardUrl, POLL_MS, type BoardState, type KrakenSettings } from "@/lib/kraken";

/** Polls the relay once a minute for this board; keeps the last good state through a failed poll. */
export function useBoard(settings: KrakenSettings | null): { state: BoardState | null; error: string | null } {
  const [state, setState] = useState<BoardState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const url = settings ? boardUrl(settings) : null;

  useEffect(() => {
    setState(null);
    setError(null);
    if (!url) return;
    let cancelled = false;
    const poll = async () => {
      try {
        const response = await fetch(url);
        if (!response.ok) throw new Error(response.status === 429 ? "Too many requests" : `Relay answered ${response.status}`);
        const next = (await response.json()) as BoardState;
        if (!cancelled) {
          setState(next);
          setError(null);
        }
      } catch (caught) {
        if (!cancelled) setError(caught instanceof Error ? caught.message : String(caught));
      }
    };
    void poll();
    const timer = window.setInterval(poll, POLL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [url]);

  return { state, error };
}

/** Unix seconds, ticking every 15 seconds for the age line. */
export function useNow(): number {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Math.floor(Date.now() / 1000)), 15_000);
    return () => window.clearInterval(timer);
  }, []);
  return now;
}

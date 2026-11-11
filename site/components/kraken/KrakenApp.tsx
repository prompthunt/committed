"use client";

import { useEffect, useState } from "react";
import { loadSettings, settingsFromQuery, STORAGE_KEY, type KrakenSettings } from "@/lib/kraken";
import { KrakenFace, type Shape } from "./KrakenFace";
import { KrakenSetup } from "./KrakenSetup";
import { useBoard, useNow } from "./useBoard";

type Mode = "kraken" | "setup";

/** CAM's Kraken Browser adds `?kraken=1`; its Configuration Browser (and any other browser) doesn't. */
export function KrakenApp() {
  const [mode, setMode] = useState<Mode | null>(null);
  useEffect(() => {
    setMode(new URLSearchParams(window.location.search).get("kraken") === "1" ? "kraken" : "setup");
  }, []);
  if (mode === null) return null;
  return mode === "kraken" ? <KrakenView /> : <KrakenSetup />;
}

interface Display {
  size: number;
  shape: Shape;
}

function readDisplay(): Display {
  const nzxt = window.nzxt?.v1;
  const size = Math.round(nzxt?.width || Math.min(window.innerWidth, window.innerHeight) || 320);
  // Every Kraken LCD is round except the 240 × 240 Kraken's square screen.
  const shape: Shape = nzxt?.shape === "square" || nzxt?.shape === "circle" ? nzxt.shape : size <= 240 ? "square" : "circle";
  return { size, shape };
}

function KrakenView() {
  const [display, setDisplay] = useState<Display>(readDisplay);
  const [settings, setSettings] = useState<KrakenSettings | null>(
    () => settingsFromQuery(new URLSearchParams(window.location.search)) ?? loadSettings(),
  );
  const { state, error } = useBoard(settings);
  const now = useNow();

  useEffect(() => {
    const fromQuery = settingsFromQuery(new URLSearchParams(window.location.search)) !== null;
    // CAM's setup page saves to the shared localStorage; the Kraken Browser never reloads, so follow it live.
    const onStorage = (event: StorageEvent) => {
      if (!fromQuery && (event.key === STORAGE_KEY || event.key === null)) setSettings(loadSettings());
    };
    const onResize = () => setDisplay(readDisplay());
    window.addEventListener("storage", onStorage);
    window.addEventListener("resize", onResize);
    return () => {
      window.removeEventListener("storage", onStorage);
      window.removeEventListener("resize", onResize);
    };
  }, []);

  const message = !settings
    ? "Set up your board in NZXT CAM"
    : !state && error
      ? "Can’t reach Committed right now"
      : null;

  return (
    <main className="fixed inset-0 flex items-center justify-center overflow-hidden bg-ink">
      <KrakenFace
        size={display.size}
        shape={display.shape}
        window={settings?.window ?? "daily"}
        state={message ? null : state}
        message={message}
        now={now}
      />
    </main>
  );
}

declare global {
  interface Window {
    nzxt?: { v1?: { width?: number; height?: number; shape?: string; targetFps?: number } };
  }
}

import type { Metadata } from "next";
import { KrakenApp } from "@/components/kraken/KrakenApp";

const title = "Committed for NZXT Kraken";
const description = "Show your Committed rank on an NZXT Kraken LCD with NZXT CAM’s Web Integration.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/kraken" },
  openGraph: { type: "website", url: "/kraken", siteName: "Committed", title, description },
};

/** NZXT CAM loads this page for setup, and again with `?kraken=1` to draw the LCD. */
export default function Kraken() {
  return <KrakenApp />;
}

import type { Metadata } from "next";
import { Inter } from "next/font/google";
import localFont from "next/font/local";
import "./globals.css";

const font = Inter({ subsets: ["latin"] });

// Committed's display face, from the app (CommitStandingsLiveRank/Fonts, SIL OFL).
const interTight = localFont({
  src: [
    { path: "./fonts/InterTight-Regular.ttf", weight: "400" },
    { path: "./fonts/InterTight-ExtraBold.ttf", weight: "800" },
  ],
  variable: "--font-inter-tight",
});

export const metadata: Metadata = {
  title: "App Store Screenshots",
  description: "Design and export App Store + Google Play screenshots.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${font.className} ${interTight.variable}`}>{children}</body>
    </html>
  );
}

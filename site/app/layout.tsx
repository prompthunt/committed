import type { Metadata, Viewport } from "next";
import { Inter, Inter_Tight } from "next/font/google";
import Script from "next/script";
import "./globals.css";

const interTight = Inter_Tight({ subsets: ["latin"], variable: "--font-inter-tight", display: "swap" });
const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });

const title = "Committed — A little friendly competition";
const description =
  "A friendly GitHub leaderboard for your Mac’s menu bar. Compare contributions with friends and teammates, with optional alerts when ranks change.";

export const metadata: Metadata = {
  metadataBase: new URL("https://gitcommitted.app"),
  title,
  description,
  applicationName: "Committed",
  alternates: { canonical: "/" },
  openGraph: { type: "website", url: "/", siteName: "Committed", title, description },
  twitter: { card: "summary_large_image", title, description },
};

export const viewport: Viewport = { themeColor: "#050505", colorScheme: "dark" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${interTight.variable} ${inter.variable}`}>
      <body>
        {children}
        <Script
          src="https://static.cloudflareinsights.com/beacon.min.js"
          data-cf-beacon='{"token":"e0315d91ca874fcb89bcde3a17d5ae95"}'
          strategy="afterInteractive"
        />
      </body>
    </html>
  );
}

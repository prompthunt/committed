import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { GLYPH_PATH } from "@/lib/glyph";

export const dynamic = "force-static";
export const alt = "Committed — A little friendly competition";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage() {
  const [regular, extraBold] = await Promise.all([
    readFile(join(process.cwd(), "app/fonts/InterTight-Regular.ttf")),
    readFile(join(process.cwd(), "app/fonts/InterTight-ExtraBold.ttf")),
  ]);
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "0 96px",
          background: "#050505",
          color: "#ffffff",
          fontFamily: "Inter Tight",
        }}
      >
        <svg width="112" height="112" viewBox="0 0 16 16">
          <path d={GLYPH_PATH} fill="#C8FF2E" />
        </svg>
        <div style={{ display: "flex", flexDirection: "column", marginTop: 40, fontSize: 96, fontWeight: 800, letterSpacing: -4, lineHeight: 1 }}>
          <span>A little friendly</span>
          <span style={{ color: "#C8FF2E" }}>competition.</span>
        </div>
        <div style={{ display: "flex", marginTop: 28, fontSize: 34, color: "#8E9288" }}>
          A GitHub leaderboard in your Mac’s menu bar.
        </div>
      </div>
    ),
    {
      ...size,
      fonts: [
        { name: "Inter Tight", data: regular, weight: 400, style: "normal" },
        { name: "Inter Tight", data: extraBold, weight: 800, style: "normal" },
      ],
    },
  );
}

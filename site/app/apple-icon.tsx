import { ImageResponse } from "next/og";
import { GLYPH_PATH } from "@/lib/glyph";

export const dynamic = "force-static";
export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div style={{ display: "flex", width: "100%", height: "100%", alignItems: "center", justifyContent: "center", background: "#050505" }}>
        <svg width="120" height="120" viewBox="0 0 16 16">
          <path d={GLYPH_PATH} fill="#C8FF2E" />
        </svg>
      </div>
    ),
    size,
  );
}

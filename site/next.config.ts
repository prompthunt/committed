import type { NextConfig } from "next";

// Fully static marketing site: `next build` writes plain HTML/CSS/JS to `out/`,
// which any static host (Cloudflare, Vercel, GitHub Pages) can serve.
const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
  trailingSlash: false,
};

export default nextConfig;

// Puts the iPhone Duo capture into Apple's bezel (public/frames), for the iPhone set's Duo screen.
// The editor frames iPhone screens in an iPhone bezel, so the Duo arrives as a framed image placed
// with an image element.
//
//   node scripts/frame-duo.mjs
//
// Reads public/screenshots/apple/duo/inner.png (2853 × 2007, the open inner display straight from
// the iPhone Duo simulator) and writes public/screenshots/apple/duo/open-framed.png.
import sharp from "sharp";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..", "public");
const jobs = [
  // The bezel's transparent screen cutout, measured from the PNG: it matches the capture exactly.
  { capture: "inner.png", frame: "duo-inner-landscape.png", left: 120, top: 120, size: [2853, 2007], out: "open-framed.png" },
];

for (const job of jobs) {
  const dir = path.join(root, "screenshots/apple/duo");
  const frame = path.join(root, "frames", job.frame);
  const { width, height } = await sharp(frame).metadata();
  const capture = await sharp(path.join(dir, job.capture)).metadata();
  if (capture.width !== job.size[0] || capture.height !== job.size[1]) {
    throw new Error(`${job.capture} is ${capture.width} × ${capture.height}, not ${job.size.join(" × ")}`);
  }
  await sharp({ create: { width, height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([
      { input: path.join(dir, job.capture), left: job.left, top: job.top },
      { input: frame, left: 0, top: 0 },
    ])
    .png()
    .toFile(path.join(dir, job.out));
  console.log(job.out, `${width} × ${height}`);
}

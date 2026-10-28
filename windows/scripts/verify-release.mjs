import { verifyRelease } from "./release-assets.mjs";
const [directory, version, commit] = process.argv.slice(2);
if (!directory || !version || !commit)
  throw Error("Usage: verify-release.mjs directory version commit");
console.log(verifyRelease(directory, version, commit));

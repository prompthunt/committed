export type DownloadPlatform = "iphone" | "mac" | "windows" | "unknown";

type BrowserPlatform = {
  userAgent: string;
  platform: string;
  maxTouchPoints: number;
  userAgentData?: { platform: string; mobile: boolean };
};

/** Select the primary download for the device, including iPads in desktop mode. */
export function detectDownloadPlatform(browser: BrowserPlatform): DownloadPlatform {
  const { userAgent, platform, maxTouchPoints, userAgentData } = browser;
  if (/iPhone|iPad|iPod/i.test(userAgent) || (/Mac/i.test(platform) && maxTouchPoints > 1)) {
    return "iphone";
  }
  if (userAgentData?.mobile || /Android|Mobile|Windows Phone/i.test(userAgent)) {
    return "unknown";
  }

  if (userAgentData?.platform) {
    if (userAgentData.platform === "Windows") return "windows";
    if (userAgentData.platform === "macOS") return "mac";
    return "unknown";
  }
  if (/Windows NT/i.test(userAgent)) return "windows";
  if (/Macintosh|Mac OS X/i.test(userAgent)) return "mac";
  return "unknown";
}

export function downloadTargets(platform: DownloadPlatform): ("iPhone" | "Mac" | "Windows")[] {
  if (platform === "iphone") return ["iPhone", "Mac"];
  if (platform === "windows") return ["Windows", "iPhone"];
  if (platform === "mac") return ["Mac", "iPhone"];
  return ["Mac", "Windows", "iPhone"];
}

// Page-wide copy shared by the metadata, the FAQ and the JSON-LD, so they can't drift apart.

export const SITE_URL = "https://gitcommitted.app";
export const WINDOWS_DOWNLOAD_AVAILABLE = process.env.NEXT_PUBLIC_WINDOWS_DOWNLOAD_AVAILABLE === "true";

export const TITLE = "Committed — A GitHub leaderboard for Mac and Windows";
export const DESCRIPTION =
  "A free, open-source GitHub leaderboard for your Mac’s menu bar or Windows tray. Compare contributions with friends and teammates, and get alerts when ranks change.";

/** Answers are plain text: they render on the page and go verbatim into the FAQPage schema. */
export const FAQ = [
  {
    q: "Is Committed free?",
    a: "Yes. Committed is free and open source under the MIT license. There's no account to create, no subscription, and nothing to buy.",
  },
  {
    q: "Do my friends need to install Committed?",
    a: "No. Committed reads each person's public GitHub contribution graph, so anyone you follow or share an organization with can appear on your board.",
  },
  {
    q: "What does the leaderboard count?",
    a: "The contributions on each person's GitHub contribution graph, the green squares, for today, the last 7 days, or the last 30 days. It compares activity, not code quality or work performance.",
  },
  {
    q: "What GitHub access does Committed need?",
    a: "Read-only access to your profile, who you follow, and your organizations. It never asks for repository access or reads your code. Your token stays in the Mac's Keychain or Windows Credential Manager.",
  },
  {
    q: "Do private contributions count?",
    a: "Only when that person turns on private contributions in their GitHub profile settings. Otherwise private work stays off their public graph, so Committed can't count it.",
  },
  {
    q: "Who shows up on my board?",
    a: "You, the people you follow, and members of your GitHub organizations. Hide anyone from People, and show them again whenever you like.",
  },
  {
    q: "How often does the board update?",
    a: "About every 5 minutes in the background. Turn on notifications to hear when you pass a friend or they pass you.",
  },
  {
    q: "Which computers does it run on?",
    a: `Macs running macOS 26 or later, with Apple silicon or Intel, and Windows 11 PCs. The Windows installer is x64; ARM PCs use x64 emulation. There's no iPhone or web app.${WINDOWS_DOWNLOAD_AVAILABLE ? "" : " The Windows download is coming with the next release."}`,
  },
  {
    q: "Why does Windows show a SmartScreen prompt?",
    a: "The Windows installer is unsigned. Choose More info → Run anyway to continue. Installation is just for your Windows user and does not need administrator rights. Automatic updates are verified with a separate updater signature.",
  },
] as const;

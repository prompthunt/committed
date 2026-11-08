import type { Metadata } from "next";
import { Bullets, ContactEmail, ReadingPage, Section } from "@/components/SiteChrome";
import { ISSUES_URL, PRIVACY_EFFECTIVE_DATE, SECURITY_REPORT_URL } from "@/lib/site";

const title = "Privacy policy — Committed";
const description = "What Committed for iPhone, Mac and Windows sends, where it goes, and what the Committed relay receives for Live rank.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/privacy" },
  openGraph: { type: "website", url: "/privacy", siteName: "Committed", title, description },
  twitter: { card: "summary_large_image", title, description },
};

// Every statement here is grounded in the code: the apps' GitHub clients and token
// stores, relay/ (what the device API accepts and the D1 schema stores), the Sparkle
// and Tauri updater feeds, and lib/analytics.ts plus the beacon in app/layout.tsx.
// Change this page when any of those change.
export default function Privacy() {
  return (
    <ReadingPage
      eyebrow="Privacy"
      title="Privacy policy"
      intro={
        <>
          <p>Committed is made by Prompt Hunt, Inc. There’s no Committed account. The apps talk to GitHub directly, and the only other service they use is the Committed relay, for Live rank on iPhone.</p>
          <p className="text-base text-muted">Effective {PRIVACY_EFFECTIVE_DATE}</p>
        </>
      }
    >
      <Section id="apps" title="The iPhone, Mac and Windows apps">
        <p>Your GitHub token stays on your device and goes only to GitHub.</p>
        <Bullets>
          <li><strong>Connect GitHub</strong> gives Committed read-only access to your profile, who you follow, and your organizations (<code>read:user read:org</code>). It never asks for repository access or reads your code.</li>
          <li>The token is stored in the iPhone’s or Mac’s Keychain, or in Windows Credential Manager. <strong>Disconnect GitHub</strong> deletes it.</li>
          <li>GitHub API calls go straight from your device to GitHub. Contributions come from each person’s public GitHub contribution page, which the apps read anonymously.</li>
          <li>Your people list, Contributions, and the people you hide are saved on your device. They aren’t synced between your devices.</li>
          <li>Leaderboard Notifications are created on your device.</li>
          <li>The apps contain no analytics or crash reporting.</li>
        </Bullets>
      </Section>

      <Section id="relay" title="The Committed relay">
        <p>The Committed relay keeps Live rank current in the Dynamic Island and on the Lock Screen while the iPhone app is closed. It’s used only while Live rank is on. Before Live rank first turns on, the app shows what the relay receives and asks you to turn it on.</p>
        <h3>What it receives</h3>
        <Bullets>
          <li>Your GitHub username and the usernames on your board, in board order. These are public.</li>
          <li>Live rank’s Window and your time zone.</li>
          <li>The Apple push tokens that update Live rank on your iPhone, and whether your build uses Apple’s test or production push service.</li>
          <li>A random installation ID and secret your iPhone creates. The relay stores only a hash of the secret.</li>
        </Bullets>
        <p>It never receives your GitHub token. That’s sent only to GitHub.</p>
        <h3>What it does</h3>
        <p>Every 5 minutes, the relay reads the public contribution pages of the usernames it has, anonymously, and keeps the daily counts in a cache shared by everyone. It ranks your board and sends Live rank updates through Apple’s push service. It doesn’t send notifications. The relay runs on Cloudflare.</p>
        <h3>Stopping it</h3>
        <p>Turning Live rank off in Settings, or <strong>Disconnect GitHub</strong>, deletes your iPhone’s registration from the relay. The relay keeps a registration until then, so do one of these before you delete the app.</p>
      </Section>

      <Section id="sample-board" title="The Sample board">
        <p>The Sample board runs on built-in sample data. It needs no GitHub account and sends nothing over the network, including to the Committed relay. Live rank on the Sample board stays on your iPhone.</p>
      </Section>

      <Section id="updates" title="Update checks on Mac and Windows">
        <p>The Mac and Windows apps check Committed’s GitHub Releases for new versions and download updates from there. These requests carry no GitHub account data. On iPhone, the App Store handles updates.</p>
      </Section>

      <Section id="website" title="This website">
        <p>gitcommitted.app measures visits with PostHog and Cloudflare Web Analytics.</p>
        <Bullets>
          <li>PostHog runs without cookies or person profiles. It records page views, when you leave a page, and clicks on download and GitHub links.</li>
          <li>PostHog doesn’t record sessions, heatmaps, or other clicks, and runs only on gitcommitted.app.</li>
          <li>Every link and download works with analytics blocked.</li>
        </Bullets>
      </Section>

      <Section id="changes" title="Changes">
        <p>When what Committed sends changes, this page and its effective date change with it.</p>
      </Section>

      <Section id="contact" title="Contact">
        <Bullets>
          <li>Email: <ContactEmail /></li>
          <li>Questions and bugs: <a href={ISSUES_URL}>GitHub Issues</a></li>
          <li>Security issues: <a href={SECURITY_REPORT_URL}>report privately on GitHub</a></li>
        </Bullets>
      </Section>
    </ReadingPage>
  );
}

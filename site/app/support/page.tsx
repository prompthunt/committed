import type { Metadata } from "next";
import { Bullets, ContactEmail, ReadingPage, Section } from "@/components/SiteChrome";
import { ISSUES_URL, SECURITY_REPORT_URL } from "@/lib/site";

const title = "Support — Committed";
const description = "Get help with Committed for iPhone, Mac and Windows: contact, common questions, and GitHub Issues.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/support" },
  openGraph: { type: "website", url: "/support", siteName: "Committed", title, description },
  twitter: { card: "summary_large_image", title, description },
};

export default function Support() {
  return (
    <ReadingPage
      eyebrow="Support"
      title="Get help"
      intro={<p>Help with Committed for iPhone, Mac and Windows.</p>}
    >
      <Section id="contact" title="Contact">
        <Bullets>
          <li>Email: <ContactEmail /></li>
          <li>Report a bug or ask a question: <a href={ISSUES_URL}>GitHub Issues</a></li>
          <li>Security issues: <a href={SECURITY_REPORT_URL}>report privately on GitHub</a></li>
        </Bullets>
      </Section>

      <Section id="questions" title="Common questions">
        <h3>Why are an organization’s members missing?</h3>
        <p>The organization limits which apps can see its members. Committed leaves it off your board, and the people sync status names it. An organization owner can approve Committed in the organization’s settings.</p>
        <p>You and the people you follow still load. Organizations GitHub doesn’t show to Committed can’t appear.</p>

        <h3>Why is a friend’s count low?</h3>
        <p>Private contributions count only once that person turns them on in GitHub. Until then, private work stays off their public graph, so Committed can’t count it.</p>
        <p>To turn them on: on GitHub, click your profile picture, then <strong>Your profile</strong>. Above the green squares, open <strong>Contribution settings</strong> and check <strong>Private contributions</strong>. Everyone does this for their own account. Others see only the counts, not which private repos they came from.</p>

        <h3>What does Live rank send to the Committed relay?</h3>
        <p>Live rank keeps your rank in the Dynamic Island and on the Lock Screen. To keep it current while the app is closed, the Committed relay receives your GitHub username, the usernames on your board, Live rank’s Window, your time zone, and the tokens that update Live rank on your iPhone.</p>
        <p>It never receives your GitHub token. Turning Live rank off in Settings, or <strong>Disconnect GitHub</strong>, deletes your iPhone’s registration from the relay. <a href="/privacy#relay">More in the privacy policy</a>.</p>

        <h3>How do I hide someone?</h3>
        <p>Open <strong>People</strong> (a tab on iPhone, <strong>People…</strong> on Mac and Windows) and tap or click the eye next to them. They leave the board but stay in People, so you can show them again with the eye-slash.</p>
        <p>Hiding someone doesn’t change who you follow on GitHub. It’s saved only on that device. You can’t hide yourself.</p>
      </Section>
    </ReadingPage>
  );
}

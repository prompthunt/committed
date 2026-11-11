import { createHttpApnsSender, type ApnsSender } from "./apns";
import { createRelay, type GitHubFetch } from "./relay";

/** Anonymous fetch of the public contributions calendar: the same page the apps read. */
export const fetchContributionsPage: GitHubFetch = async (login) => {
  const response = await fetch(`https://github.com/users/${encodeURIComponent(login)}/contributions`, {
    headers: { "user-agent": "Committed-Relay (+https://github.com/prompthunt/committed)", accept: "text/html" },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.text();
};

const nowSeconds = () => Math.floor(Date.now() / 1000);

function relayFor(env: Env) {
  const apns: ApnsSender = createHttpApnsSender({
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    privateKey: env.APNS_PRIVATE_KEY,
    bundleId: env.APNS_BUNDLE_ID,
    now: nowSeconds,
    origin: env.APNS_ORIGIN || undefined,
  });
  return createRelay({
    db: env.DB,
    apns,
    github: fetchContributionsPage,
    now: nowSeconds,
    bundleId: env.APNS_BUNDLE_ID,
    boardLimiter: env.BOARD_LIMITER,
  });
}

export default {
  fetch(request, env) {
    return relayFor(env).fetch(request);
  },
  scheduled(_controller, env, ctx) {
    ctx.waitUntil(relayFor(env).runCycle());
  },
} satisfies ExportedHandler<Env>;

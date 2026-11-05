declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    /** iOS app bundle id; the APNs topic is `${APNS_BUNDLE_ID}.push-type.liveactivity`. */
    APNS_BUNDLE_ID: string;
    /** Secrets. */
    APNS_KEY_ID: string;
    APNS_TEAM_ID: string;
    /** Contents of the `.p8` key (PEM, PKCS#8). */
    APNS_PRIVATE_KEY: string;
    /** Test-only: D1 migrations read by vitest.config.ts. */
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}
interface Env extends Cloudflare.Env {}
declare namespace Cloudflare {
  interface GlobalProps {
    mainModule: typeof import("./index");
  }
}

/** Bindings and configuration for the Committed relay Worker. */
export interface Env {
  DB: D1Database;
  /** The iOS app's bundle ID (a var). The APNs topic is `<bundle>.push-type.liveactivity`. */
  APNS_BUNDLE_ID: string;
  /** Outbound requests per cron run (a var, default 50: the free plan's limit). See README "Limits". */
  SUBREQUEST_LIMIT?: string;
  /** Most GitHub fetches per cron run (a var, default 40), within SUBREQUEST_LIMIT minus the APNs reserve. */
  GITHUB_FETCH_BUDGET?: string;
  /** Apple Developer team ID (secret). */
  APNS_TEAM_ID?: string;
  /** Key ID of the APNs auth key (secret). */
  APNS_KEY_ID?: string;
  /** The `.p8` APNs auth key, PEM text (secret). */
  APNS_PRIVATE_KEY?: string;
}

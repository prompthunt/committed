/** Bindings and configuration for the Committed relay Worker. */
export interface Env {
  DB: D1Database;
  /** The iOS app's bundle ID (a var). The APNs topic is `<bundle>.push-type.liveactivity`. */
  APNS_BUNDLE_ID: string;
  /** Apple Developer team ID (secret). */
  APNS_TEAM_ID?: string;
  /** Key ID of the APNs auth key (secret). */
  APNS_KEY_ID?: string;
  /** The `.p8` APNs auth key, PEM text (secret). */
  APNS_PRIVATE_KEY?: string;
}

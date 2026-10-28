export type Window = 'today' | 'week' | 'month';
export interface Person {
  login: string; name: string | null; avatar_url: string | null;
  following?: boolean; organizations?: string[];
}
export interface Row extends Person {
  rank: number; contributions: number | null; is_you: boolean; movement: number;
  status: 'loaded' | 'loading' | 'failed' | 'missing';
}
export interface Board {
  window: Window; rows: Row[]; owner: string | null; refreshing: boolean;
  last_updated: number | null; error: string | null;
  people_updated: number | null; people_error: string | null;
}
export interface Settings { notifications: boolean; automatic_updates: boolean; private_tip_dismissed: boolean }
export interface DesktopSettings { launch_at_login: boolean; version: string }
export interface PersonVisibility { person: Person; hidden: boolean; is_you: boolean }

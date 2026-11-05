// The only logging path. Install IDs are shortened; push tokens, secrets, and request bodies are
// never passed here, so they can't reach Workers Logs.

export type Log = (line: string) => void;

type Field = string | number | boolean | undefined;

export function logEvent(log: Log, event: string, fields: { install?: string } & Record<string, Field> = {}): void {
  const entry: Record<string, Field> = { event };
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined) continue;
    entry[key] = key === "install" && typeof value === "string" ? value.slice(0, 8) : value;
  }
  log(JSON.stringify(entry));
}

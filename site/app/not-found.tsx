import Link from "next/link";
import { AppIcon } from "@/components/Glyph";

export default function NotFound() {
  return (
    <main className="flex min-h-svh flex-col items-center justify-center gap-6 px-5 text-center">
      <AppIcon size={96} />
      <h1 className="text-5xl font-bold tracking-tight">404</h1>
      <p className="text-soft">Page not found.</p>
      <Link href="/" className="rounded-xl bg-lime px-6 py-4 font-semibold text-ink">Committed</Link>
    </main>
  );
}

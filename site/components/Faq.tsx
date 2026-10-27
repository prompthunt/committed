import { FAQ } from "@/lib/site";

/** Common questions, as native disclosure rows. The same copy feeds the FAQPage JSON-LD. */
export function Faq() {
  return (
    <section aria-labelledby="faq-title" className="mx-auto grid w-full max-w-[1240px] gap-8 pt-[clamp(56px,7vw,112px)] lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-12">
      <div>
        <p className="font-mono text-[11px] font-medium tracking-[.06em] text-muted uppercase">FAQ</p>
        <h2 id="faq-title" className="mt-4 text-[clamp(32px,4.4vw,56px)] leading-[0.95] font-[750] tracking-[-0.05em] text-balance">
          Questions, answered.
        </h2>
      </div>
      <div className="border-t border-white/[.08]">
        {FAQ.map(({ q, a }) => (
          <details key={q} className="group border-b border-white/[.08]">
            <summary className="flex min-h-16 cursor-pointer list-none items-center justify-between gap-6 py-4 text-lg font-semibold tracking-[-0.01em] transition-colors hover:text-lime [&::-webkit-details-marker]:hidden">
              {q}
              <svg aria-hidden width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" className="shrink-0 text-muted transition-transform duration-200 group-open:rotate-45">
                <path d="M8 2.5v11M2.5 8h11" />
              </svg>
            </summary>
            <p className="max-w-[36rem] pb-6 text-base leading-relaxed text-soft">{a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

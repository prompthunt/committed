"use client";

import type { ComponentProps } from "react";
import { captureLink } from "@/lib/analytics";

type Props = Omit<ComponentProps<"a">, "onClick" | "onAuxClick"> & {
  event: "download_clicked" | "github_clicked";
  placement: "hero" | "header" | "footer";
};

export function AnalyticsLink({ event, placement, ...props }: Props) {
  return (
    <a
      {...props}
      onClick={() => captureLink(event, placement)}
      onAuxClick={(click) => { if (click.button === 1) captureLink(event, placement); }}
    />
  );
}

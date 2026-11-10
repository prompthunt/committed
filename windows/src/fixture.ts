// Dev-only entry for `fixture.html`: answers the app's Tauri commands with the Sample board so
// any view renders in a plain browser. Query: `view` (board, people, about; default board).
import { mockIPC } from "@tauri-apps/api/mocks";
import { start } from "./app";
import { sampleBoard, samplePeopleList } from "./sample-board";
import type { Window } from "./types";
import "./style.css";

const now = Math.floor(Date.now() / 1000);
mockIPC(
  (command, args) => {
    const payload = (args ?? {}) as Record<string, unknown>;
    switch (command) {
      case "get_board":
        return sampleBoard(payload.window as Window, now);
      case "get_settings":
        return {
          notifications: true,
          automatic_updates: true,
          private_tip_dismissed: true,
        };
      case "get_desktop_settings":
        return { launch_at_login: false, version: "0.0.0-fixture" };
      case "list_people":
        return samplePeopleList();
      default:
        // get_avatar (letter fallback), get_update_status, select_window, request_refresh…
        return null;
    }
  },
  { shouldMockEvents: true },
);
const root = document.querySelector<HTMLElement>("#app")!;
start(root, new URLSearchParams(location.search).get("view") ?? "board").catch(
  (error) => {
    root.textContent = `Fixture could not load: ${String(error)}`;
  },
);

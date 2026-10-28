import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { Board, DesktopSettings, Person, PersonVisibility, Settings, Window } from './types';

const windows: [Window, string][] = [['today', 'Today'], ['week', '7 days'], ['month', '30 days']];
const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const name = (p: Person) => p.name?.trim() || p.login;
const count = (value: number | null) => value === null ? '—' : value.toLocaleString();
const age = (timestamp: number | null) => timestamp === null ? 'Not refreshed yet' : `Updated ${Math.max(0, Math.floor((Date.now() / 1000 - timestamp) / 60))} min ago`;
function avatar(person: Person) {
  // Never interpolate an arbitrary remote URL into a webview resource.
  const allowed = person.avatar_url?.startsWith('https://avatars.githubusercontent.com/');
  return allowed ? `<img class="avatar" src="${escape(person.avatar_url)}" alt="" referrerpolicy="no-referrer">` : `<span class="avatar fallback" aria-hidden="true">${escape(name(person).slice(0, 1).toUpperCase())}</span>`;
}
export async function start(root: HTMLElement, view: string): Promise<() => void> {
  let selected: Window = 'today';
  let filter = 'all'; let search = ''; let disposed = false;
  let pollTimer: ReturnType<typeof setTimeout> | undefined;
  let status = ''; let updateReady = false; let loadRevision = 0;
  let settings: Settings; let desktop: DesktopSettings;
  const act = async (command: string, args?: Record<string, unknown>) => {
    try { await invoke(command, args); }
    catch (error) { showError(String(error)); }
  };
  function showError(error: string) {
    const alert = root.querySelector<HTMLElement>('#error');
    if (alert) { alert.textContent = error; alert.hidden = false; }
  }
  function replace(html: string) {
    const active = document.activeElement as HTMLInputElement | null;
    const focus = active?.dataset.focus;
    const selection = active?.tagName === 'INPUT' ? active.selectionStart : null;
    const menuOpen = root.querySelector<HTMLDetailsElement>('details')?.open;
    root.innerHTML = html;
    if (menuOpen && root.querySelector('details')) root.querySelector('details')!.open = true;
    if (focus) {
      const next = Array.from(root.querySelectorAll<HTMLElement>('[data-focus]')).find(el => el.dataset.focus === focus);
      next?.focus();
      if (selection !== null && next?.tagName === 'INPUT') (next as HTMLInputElement).setSelectionRange(selection, selection);
    }
  }
  const alert = () => '<p id="error" class="error" role="alert" hidden></p>';
  function menu(board: Board) {
    return `<details class="menu"><summary aria-label="More options" data-focus="menu">⋯</summary><div class="menu-items">
      <button data-action="refresh" data-focus="refresh">Refresh <small>${age(board.last_updated)}</small></button>
      <button data-action="people">People…</button><button data-action="about">About Committed</button><hr>
      <label><input type="checkbox" data-setting="notifications" ${settings.notifications ? 'checked' : ''}> Leaderboard Notifications</label>
      <label><input type="checkbox" data-setting="launch_at_login" ${desktop.launch_at_login ? 'checked' : ''}> Launch at Login</label>
      <label><input type="checkbox" data-setting="automatic_updates" ${settings.automatic_updates ? 'checked' : ''}> Automatic Updates</label>
      <button data-action="check-update">Check for Updates…</button><hr>
      <button data-action="disconnect">Disconnect GitHub</button><button data-action="quit">Quit</button>
    </div></details>`;
  }
  async function load() {
    const revision = ++loadRevision;
    const [currentSettings, desktopSettings, board, update] = await Promise.all([
      invoke<Settings>('get_settings'), invoke<DesktopSettings>('get_desktop_settings'), invoke<Board>('get_board', { window: selected }),
      invoke<{ message: string; ready: boolean } | null>('get_update_status'),
    ]);
    if (disposed || revision !== loadRevision) return;
    settings = currentSettings; desktop = desktopSettings;
    if (update) { status = update.message; updateReady = update.ready; }
    if (view === 'about') {
      replace(`<article class="about"><span class="brand-mark" aria-hidden="true">▦</span><h1>Committed</h1><p>A friendly GitHub leaderboard, one click from your tray.</p><p class="muted">Version ${escape(desktop.version)}</p><h2>What counts?</h2><p>Contributions are the green squares on each person’s public GitHub contribution graph. Today, 7 days, and 30 days include today in your local time zone.</p><h2>Private contributions</h2><p>Private activity counts only when that person enables <strong>Contribution settings → Private contributions</strong> on their GitHub profile.</p><p>Connecting requests read-only profile and organization access. Committed never requests repository access. Your token stays in Windows Credential Manager.</p><button data-action="contributions">Open GitHub profile settings</button>${alert()}</article>`);
    } else if (view === 'people') {
      const people = await invoke<PersonVisibility[]>('list_people', { search, filter });
      if (disposed || revision !== loadRevision) return;
      replace(`<header><h1>People</h1><small>${age(board.people_updated)}</small></header><p class="muted">Your follows and organization members. Visibility changes only this PC.</p>
        <label class="search-label">Search People<input type="search" placeholder="Name or username" value="${escape(search)}" data-focus="search" id="search"></label>
        <label class="filter-label">Source<select id="filter" data-focus="filter"><option value="all">All</option><option value="following" ${filter === 'following' ? 'selected' : ''}>Following</option><option value="organizations" ${filter === 'organizations' ? 'selected' : ''}>Organizations</option></select></label>
        ${board.people_error ? `<p class="error" role="status">${escape(board.people_error)}</p>` : ''}
        <ul class="people-list">${people.map(({ person, hidden, is_you }) => `<li>${avatar(person)}<span class="identity"><strong>${escape(name(person))}</strong><small>@${escape(person.login)} ${is_you ? '· you' : ''}</small></span><button class="visibility" ${is_you ? 'disabled' : ''} data-person="${escape(person.login)}" data-hidden="${!hidden}" data-focus="person-${escape(person.login)}" aria-label="${hidden ? 'Show' : 'Hide'} ${escape(name(person))}" aria-pressed="${!hidden}"><span aria-hidden="true">${hidden ? '◌' : '◉'}</span> ${hidden ? 'Show' : 'Hide'}</button></li>`).join('')}</ul>
        ${people.length ? '' : '<p class="muted">No people match this search.</p>'}${alert()}`);
    } else if (view === 'setup') {
      if (!root.querySelector('#connect')) replace(`<article class="setup"><span class="brand-mark" aria-hidden="true">▦</span><h1>Your people.<br>Your leaderboard.</h1><p>Connect GitHub to compare Contributions with the people you follow and members of your organizations.</p><p class="muted">Read-only profile and organization access. No repository access. Your token stays in Windows Credential Manager.</p><div id="device" role="status" aria-live="polite"></div><button class="primary" id="connect" data-action="connect">Connect GitHub</button><button data-action="open-device" id="open-device" hidden>Open GitHub again</button>${alert()}</article>`);
    } else {
      const me = board.rows.find(row => row.is_you);
      const refreshing = board.refreshing;
      const first = !board.rows.some(r => r.contributions !== null);
      replace(`<header><h1><span class="brand-mark small" aria-hidden="true">▦</span> Committed</h1>${menu(board)}</header>
        ${me ? `<section class="summary">${avatar(me)}<div><strong>${escape(name(me))}</strong><small>@${escape(me.login)} · you</small></div><div class="summary-count">${count(me.contributions)}<small>Contributions</small></div></section>` : '<p>Connect GitHub to load your board.</p>'}
        <div class="windows" role="radiogroup" aria-label="Time range">${windows.map(([value, label]) => `<button role="radio" aria-checked="${selected === value}" tabindex="${selected === value ? 0 : -1}" data-window="${value}" data-focus="window-${value}">${label}</button>`).join('')}</div>
        <p class="status" role="status" aria-live="polite" aria-atomic="true">${windows.find(w => w[0] === selected)![1]} · ${refreshing ? (first ? 'Fetching the first set of standings' : 'Updating Contributions…') : board.error ? 'Refresh finished with errors.' : age(board.last_updated)}</p>
        <ol class="standings ${refreshing && !first ? 'refreshing' : ''}" aria-label="Leaderboard" aria-busy="${refreshing}">${board.rows.map(row => {
          const spoken = `Rank ${row.rank}, ${name(row)}, ${row.contributions === null ? 'Contributions unavailable' : `${row.contributions} Contributions`}${row.is_you ? ', you' : ''}`;
          return `<li class="${row.is_you ? 'you' : ''}"><button class="standing" data-profile="${escape(row.login)}" data-focus="row-${escape(row.login)}" aria-label="${escape(spoken)}"><span class="rank">${row.rank}</span>${avatar(row)}<span class="identity"><strong>${escape(name(row))}${row.is_you ? ' <span class="badge">you</span>' : ''}</strong><small>@${escape(row.login)}${row.status === 'failed' ? ' · Refresh failed' : ''}</small></span>${selected === 'today' && row.movement ? `<span class="movement ${row.movement > 0 ? 'up' : 'down'}" aria-label="Moved ${row.movement > 0 ? 'up' : 'down'} ${Math.abs(row.movement)}">${row.movement > 0 ? '↑' : '↓'}${Math.abs(row.movement)}</span>` : ''}<strong class="contributions">${count(row.contributions)}</strong></button></li>`;
        }).join('')}</ol>
        ${first && !refreshing ? '<p class="muted">Fetching the first set of standings. Use Refresh to retry if GitHub is unavailable.</p>' : ''}
        ${board.error ? `<p class="error">${escape(board.error)}</p>` : ''}
        <footer><small>${board.people_error ? escape(board.people_error) : `People · ${age(board.people_updated)}`}</small>${board.people_error ? '<button data-action="refresh">Retry</button>' : ''}</footer>
        ${settings.private_tip_dismissed ? '' : '<aside class="tip"><p>Private contributions count when each person enables them on their GitHub profile.</p><button data-action="dismiss-tip" aria-label="Dismiss private contributions tip">×</button></aside>'}
        <p id="update-status" role="status">${escape(status)}</p><button id="install-update" data-action="install-update" ${updateReady ? '' : 'hidden'}>Restart to update</button>${alert()}`);
    }
  }
  async function connect() {
    const button = root.querySelector<HTMLButtonElement>('#connect')!;
    button.disabled = true;
    try {
      const prompt = await invoke<{ user_code: string; interval: number }>('start_connect');
      const device = root.querySelector('#device')!;
      device.innerHTML = `<p>Enter this code on GitHub:</p><strong class="device-code">${escape(prompt.user_code)}</strong><p id="poll-status">Waiting for you to approve access…</p>`;
      root.querySelector<HTMLButtonElement>('#open-device')!.hidden = false;
      await act('open_github', { page: 'device' });
      const poll = async () => {
        try {
          const result = await invoke<string>('poll_connect');
          if (disposed) return;
          if (result === 'connected') { button.disabled = false; device.textContent = 'Connected. Your board is ready.'; return; }
          root.querySelector('#poll-status')!.textContent = result === 'slowDown' ? 'GitHub asked us to wait a little longer. Your code is still active.' : 'Waiting for you to approve access…';
          pollTimer = setTimeout(poll, 1000);
        } catch (error) { button.disabled = false; showError(String(error)); }
      };
      pollTimer = setTimeout(poll, Math.max(1, prompt.interval) * 1000);
    } catch (error) { button.disabled = false; showError(String(error)); }
  }
  const click = async (event: Event) => {
    const target = (event.target as HTMLElement).closest<HTMLElement>('button'); if (!target) return;
    if (target.dataset.window) {
      selected = target.dataset.window as Window;
      await load(); await act('request_refresh', { reason: 'windowChanged' });
      root.querySelector<HTMLElement>(`[data-window="${selected}"]`)?.focus(); return;
    }
    if (target.dataset.profile) { await act('open_profile', { login: target.dataset.profile }); return; }
    if (target.dataset.person) { await act('set_hidden', { login: target.dataset.person, hidden: target.dataset.hidden === 'true' }); await load(); return; }
    switch (target.dataset.action) {
      case 'connect': await connect(); break;
      case 'open-device': await act('open_github', { page: 'device' }); break;
      case 'contributions': await act('open_github', { page: 'contributions' }); break;
      case 'refresh': await act('request_refresh', { reason: 'manual' }); break;
      case 'people': case 'about': await act('open_window', { label: target.dataset.action }); break;
      case 'disconnect': await act('disconnect'); break;
      case 'quit': await act('quit'); break;
      case 'dismiss-tip': await act('set_setting', { setting: 'private_tip_dismissed', enabled: true }); await load(); break;
      case 'check-update': status = 'Checking for updates…'; await load(); await act('check_updates', { manual: true }); break;
      case 'install-update': await act('install_update'); break;
    }
  };
  const change = async (event: Event) => {
    const input = event.target as HTMLInputElement;
    if (input.dataset.setting === 'launch_at_login') await act('set_launch_at_login', { enabled: input.checked });
    else if (input.dataset.setting) await act('set_setting', { setting: input.dataset.setting, enabled: input.checked });
    else if (input.id === 'filter') filter = input.value;
    await load();
  };
  const input = (event: Event) => { if ((event.target as HTMLElement).id === 'search') { search = (event.target as HTMLInputElement).value; void load().catch(error => showError(String(error))); } };
  const keydown = (event: KeyboardEvent) => {
    const radio = (event.target as HTMLElement).closest<HTMLElement>('[data-window]');
    if (radio && ['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) {
      event.preventDefault(); const index = windows.findIndex(w => w[0] === radio.dataset.window);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? 2 : (index + (event.key === 'ArrowRight' ? 1 : 2)) % 3;
      root.querySelector<HTMLButtonElement>(`[data-window="${windows[next][0]}"]`)?.click();
    }
    if (event.key === 'Escape') {
      const menu = root.querySelector<HTMLDetailsElement>('details[open]');
      if (menu) { menu.open = false; menu.querySelector('summary')?.focus(); }
      else if (view === 'board') void act('hide_board');
    }
  };
  root.addEventListener('click', click); root.addEventListener('change', change); root.addEventListener('input', input); root.addEventListener('keydown', keydown);
  const unlisten = await listen('board-changed', () => { void load().catch(error => showError(String(error))); });
  const unlistenError = await listen<string>('app-error', event => showError(event.payload));
  const unlistenUpdate = await listen<{ message: string; ready: boolean }>('update-status', event => {
    status = event.payload.message;
    updateReady = event.payload.ready;
    const label = root.querySelector('#update-status'); if (label) label.textContent = status;
    const install = root.querySelector<HTMLButtonElement>('#install-update'); if (install) install.hidden = !event.payload.ready;
  });
  await load();
  return () => { disposed = true; clearTimeout(pollTimer); unlisten(); unlistenError(); unlistenUpdate(); root.removeEventListener('click', click); root.removeEventListener('change', change); root.removeEventListener('input', input); root.removeEventListener('keydown', keydown); };
}

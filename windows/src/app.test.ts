// @vitest-environment jsdom
import { afterEach, expect, test, vi } from 'vitest';
import { mockIPC, clearMocks } from '@tauri-apps/api/mocks';
import { start } from './app';

const board = {
  window: 'today', owner: 'octocat', refreshing: false, error: null, people_error: null,
  last_updated: 1779969600, people_updated: 1779969600,
  rows: [{ login: 'octocat', name: 'Mona', avatar_url: null, rank: 1, contributions: 12, is_you: true, movement: 0, status: 'loaded' }],
};
afterEach(() => { clearMocks(); document.body.innerHTML = ''; });
async function mount(snapshot: unknown) {
  mockIPC((command) => {
    if (command === 'get_board') return snapshot;
    if (command === 'get_settings') return { notifications: false, automatic_updates: true, private_tip_dismissed: false };
    if (command === 'get_desktop_settings') return { launch_at_login: false, version: '0.1.50' };
    if (command === 'plugin:event|listen') return 1;
    return null;
  });
  document.body.innerHTML = '<main id="app"></main>';
  return start(document.querySelector('main')!, 'board');
}
test('board presents rank, name, contributions and you to assistive technology', async () => {
  const dispose = await mount(board);
  expect(document.querySelector('[aria-label="Rank 1, Mona, 12 Contributions, you"]')).not.toBeNull();
  expect(document.body.textContent).toContain('Today');
  dispose();
});

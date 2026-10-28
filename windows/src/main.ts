import { start } from './app';
import './style.css';
const root = document.querySelector<HTMLElement>('#app')!;
start(root, new URLSearchParams(location.search).get('view') ?? 'board').catch(error => {
  root.textContent = `Committed could not load: ${String(error)}`;
});

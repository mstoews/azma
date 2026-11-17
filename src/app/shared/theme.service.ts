import { DOCUMENT } from '@angular/common';
import { Injectable, effect, inject, signal } from '@angular/core';

export type ThemePref = 'system' | 'light' | 'dark';

const KEY = 'cms.theme';
const ORDER: ThemePref[] = ['system', 'light', 'dark'];

function read(key: string): string | null {
  try { return localStorage.getItem(key); } catch { return null; }
}
function write(key: string, value: string): void {
  try { localStorage.setItem(key, value); } catch { /* private mode: keep it in memory */ }
}

/**
 * Admin colour theme and sidebar state. The theme is set as
 * `data-cms-theme` on <html>; admin.css reads it. "system" removes the
 * attribute so prefers-color-scheme decides.
 */
@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly root = inject(DOCUMENT).documentElement;

  readonly theme = signal<ThemePref>((ORDER as string[]).includes(read(KEY) ?? '') ? (read(KEY) as ThemePref) : 'system');
  readonly collapsed = signal(read('cms.sidebar') === 'collapsed');

  constructor() {
    effect(() => {
      const t = this.theme();
      if (t === 'system') this.root.removeAttribute('data-cms-theme');
      else this.root.setAttribute('data-cms-theme', t);
      write(KEY, t);
    });
    effect(() => write('cms.sidebar', this.collapsed() ? 'collapsed' : 'expanded'));
  }

  cycle(): void {
    this.theme.update((t) => ORDER[(ORDER.indexOf(t) + 1) % ORDER.length]);
  }
}

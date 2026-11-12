import { Injectable, signal } from '@angular/core';

export interface Notice {
  kind: 'ok' | 'error';
  text: string;
}

/** A single transient status line shown at the top of the admin area. */
@Injectable({ providedIn: 'root' })
export class NoticeService {
  readonly current = signal<Notice | null>(null);
  private timer?: ReturnType<typeof setTimeout>;

  ok(text: string): void { this.show({ kind: 'ok', text }); }
  error(text: string): void { this.show({ kind: 'error', text }, 8000); }
  clear(): void { this.current.set(null); }

  private show(n: Notice, ms = 3500): void {
    clearTimeout(this.timer);
    this.current.set(n);
    this.timer = setTimeout(() => this.current.set(null), ms);
  }
}

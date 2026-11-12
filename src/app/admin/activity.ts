import { DatePipe } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { AuditEntry } from './models';

const PAGE = 50;

@Component({
  selector: 'cms-activity',
  imports: [DatePipe],
  template: `
    <header class="cms-head"><h1>Activity</h1></header>
    <p class="cms-muted">Every change made in the CMS. Each entry keeps the before/after content, so a mistake can be recovered.</p>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <table class="cms-table">
      <thead><tr><th>When</th><th>Who</th><th>What</th></tr></thead>
      <tbody>
        @for (a of rows(); track a.id) {
          <tr><td class="cms-muted">{{ a.createdAt | date: 'MMM d, y HH:mm:ss' }}</td><td>{{ a.userEmail || 'system' }}</td>
            <td>{{ a.action }} {{ a.entity }} <span class="cms-muted">{{ a.entityId }}</span></td></tr>
        }
      </tbody>
    </table>
    <div class="cms-row">
      <button type="button" class="cms-btn" [disabled]="offset() === 0" (click)="go(-1)">Newer</button>
      <button type="button" class="cms-btn" [disabled]="rows().length < page" (click)="go(1)">Older</button>
    </div>
  `,
})
export class Activity {
  private readonly api = inject(AdminApi);
  protected readonly page = PAGE;
  protected readonly rows = signal<AuditEntry[]>([]);
  protected readonly offset = signal(0);
  protected readonly error = signal('');

  constructor() {
    inject(Title).setTitle('Activity – AZMA CMS');
    this.load();
  }

  protected go(d: number): void {
    this.offset.update((o) => Math.max(0, o + d * PAGE));
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.rows.set(await this.api.audit(PAGE, this.offset()));
    } catch (e) {
      this.error.set(errorMessage(e));
    }
  }
}

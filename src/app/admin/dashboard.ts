import { DatePipe } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';
import { AdminApi } from './admin-api.service';
import { AuthService } from './auth.service';
import { errorMessage } from './auth.interceptor';
import { AuditEntry } from './models';

@Component({
  selector: 'cms-dashboard',
  imports: [RouterLink, DatePipe],
  template: `
    <header class="cms-head"><h1>Welcome{{ auth.user()?.name ? ', ' + auth.user()?.name : '' }}</h1></header>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <div class="cms-stats">
      <a routerLink="/admin/pages" class="cms-stat"><strong>{{ stats().pages }}</strong><span>Pages</span>
        @if (stats().pageDrafts) { <em>{{ stats().pageDrafts }} draft</em> }</a>
      <a routerLink="/admin/profiles" class="cms-stat"><strong>{{ stats().profiles }}</strong><span>Team profiles</span>
        @if (stats().profileDrafts) { <em>{{ stats().profileDrafts }} draft</em> }</a>
      <a routerLink="/admin/media" class="cms-stat"><strong>{{ stats().media }}</strong><span>Media files</span></a>
    </div>
    <div class="cms-row">
      <a routerLink="/admin/pages/new" class="cms-btn cms-btn-primary">New page</a>
      <a routerLink="/admin/profiles/new" class="cms-btn">New team profile</a>
      <a routerLink="/admin/media" class="cms-btn">Upload media</a>
    </div>
    <section class="cms-section">
      <h2>Recent activity</h2>
      <table class="cms-table">
        <tbody>
          @for (a of activity(); track a.id) {
            <tr><td class="cms-muted">{{ a.createdAt | date: 'MMM d, HH:mm' }}</td><td>{{ a.userEmail || 'system' }}</td><td>{{ a.action }} {{ a.entity }} {{ a.entityId }}</td></tr>
          } @empty { <tr><td class="cms-muted">Nothing yet.</td></tr> }
        </tbody>
      </table>
    </section>
  `,
})
export class Dashboard {
  private readonly api = inject(AdminApi);
  protected readonly auth = inject(AuthService);
  protected readonly stats = signal({ pages: 0, pageDrafts: 0, profiles: 0, profileDrafts: 0, media: 0 });
  protected readonly activity = signal<AuditEntry[]>([]);
  protected readonly error = signal('');

  constructor() {
    inject(Title).setTitle('Dashboard – AZMA CMS');
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const [pages, profiles, media, activity] = await Promise.all([
        this.api.pages(), this.api.profiles(), this.api.media(), this.api.audit(10),
      ]);
      this.stats.set({
        pages: pages.length, pageDrafts: pages.filter((p) => !p.published).length,
        profiles: profiles.length, profileDrafts: profiles.filter((p) => !p.published).length,
        media: media.length,
      });
      this.activity.set(activity);
    } catch (e) {
      this.error.set(errorMessage(e));
    }
  }
}

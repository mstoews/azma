import { DatePipe } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';
import { AdminApi } from './admin-api.service';
import { AuthService } from './auth.service';
import { errorMessage } from './auth.interceptor';
import { AuditEntry } from './models';
import { Icon } from './shared/icon';

@Component({
  selector: 'cms-dashboard',
  imports: [RouterLink, DatePipe, Icon],
  template: `
    <header class="cms-head">
      <div>
        <p class="cms-eyebrow">{{ today | date: 'EEEE, MMMM d' }}</p>
        <h1>{{ greeting() }}{{ auth.user()?.name ? ', ' + auth.user()?.name : '' }}</h1>
        <p class="cms-muted cms-subtitle">Here is what is happening on the AZMA site.</p>
      </div>
      <a routerLink="/admin/pages/new" class="cms-btn cms-btn-primary"><cms-icon name="plus" />New page</a>
    </header>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <div class="cms-stats">
      <a routerLink="/admin/pages" class="cms-stat">
        <span class="cms-stat-icon" data-tone="blue"><cms-icon name="page" /></span>
        <strong>{{ stats().pages }}</strong><span>Pages</span>
        @if (stats().pageDrafts) { <em>{{ stats().pageDrafts }} draft</em> } @else { <em>All published</em> }
      </a>
      <a routerLink="/admin/profiles" class="cms-stat">
        <span class="cms-stat-icon" data-tone="violet"><cms-icon name="users" /></span>
        <strong>{{ stats().profiles }}</strong><span>Team profiles</span>
        @if (stats().profileDrafts) { <em>{{ stats().profileDrafts }} draft</em> } @else { <em>All published</em> }
      </a>
      <a routerLink="/admin/media" class="cms-stat">
        <span class="cms-stat-icon" data-tone="green"><cms-icon name="image" /></span>
        <strong>{{ stats().media }}</strong><span>Media files</span><em>In the library</em>
      </a>
    </div>

    <div class="cms-dash-grid">
      <section class="cms-card cms-card-flush">
        <div class="cms-card-head"><h2>Recent activity</h2><a routerLink="/admin/activity" class="cms-link-sm">View all <cms-icon name="arrow" /></a></div>
        <ol class="cms-timeline">
          @for (a of activity(); track a.id) {
            <li>
              <span class="cms-timeline-dot" [attr.data-action]="a.action"></span>
              <div>
                <div><strong>{{ a.userEmail || 'system' }}</strong> <span class="cms-muted">{{ a.action }}</span> {{ a.entity }}
                  @if (a.entityId) { <code class="cms-pill">{{ a.entityId }}</code> }</div>
                <small class="cms-muted">{{ a.createdAt | date: 'MMM d, HH:mm' }}</small>
              </div>
            </li>
          } @empty { <li class="cms-muted cms-empty">{{ loading() ? 'Loading…' : 'Nothing yet.' }}</li> }
        </ol>
      </section>
      <section class="cms-card">
        <h2>Quick actions</h2>
        <div class="cms-quick">
          <a routerLink="/admin/pages/new"><span class="cms-stat-icon" data-tone="blue"><cms-icon name="edit" /></span>
            <span><strong>Write a page</strong><small class="cms-muted">Start a new page draft</small></span></a>
          <a routerLink="/admin/profiles/new"><span class="cms-stat-icon" data-tone="violet"><cms-icon name="users" /></span>
            <span><strong>Add a team member</strong><small class="cms-muted">Create a profile card</small></span></a>
          <a routerLink="/admin/media"><span class="cms-stat-icon" data-tone="green"><cms-icon name="upload" /></span>
            <span><strong>Upload media</strong><small class="cms-muted">Images and documents</small></span></a>
          <a routerLink="/admin/navigation"><span class="cms-stat-icon" data-tone="amber"><cms-icon name="menu" /></span>
            <span><strong>Edit the menu</strong><small class="cms-muted">Site navigation</small></span></a>
        </div>
      </section>
    </div>
  `,
})
export class Dashboard {
  private readonly api = inject(AdminApi);
  protected readonly auth = inject(AuthService);
  protected readonly stats = signal({ pages: 0, pageDrafts: 0, profiles: 0, profileDrafts: 0, media: 0 });
  protected readonly activity = signal<AuditEntry[]>([]);
  protected readonly error = signal('');
  protected readonly loading = signal(true);
  protected readonly today = new Date();
  protected readonly greeting = () => {
    const h = this.today.getHours();
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  };

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
    } finally {
      this.loading.set(false);
    }
  }
}

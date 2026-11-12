import { Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from './auth.service';
import { NoticeService } from './shared/notice.service';

@Component({
  selector: 'cms-admin-layout',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="cms" translate="no">
      <aside class="cms-sidebar">
        <a routerLink="/admin" class="cms-brand">AZMA <span>CMS</span></a>
        <nav aria-label="Admin">
          <a routerLink="/admin" routerLinkActive="active" [routerLinkActiveOptions]="{ exact: true }">Dashboard</a>
          <a routerLink="/admin/pages" routerLinkActive="active">Pages</a>
          <a routerLink="/admin/profiles" routerLinkActive="active">Team profiles</a>
          <a routerLink="/admin/navigation" routerLinkActive="active">Menu</a>
          <a routerLink="/admin/media" routerLinkActive="active">Media</a>
          <a routerLink="/admin/settings" routerLinkActive="active">Site settings</a>
          <a routerLink="/admin/users" routerLinkActive="active">Administrators</a>
          <a routerLink="/admin/activity" routerLinkActive="active">Activity</a>
        </nav>
        <div class="cms-sidebar-foot">
          <a href="/" target="_blank" rel="noopener">View site ↗</a>
          <a routerLink="/admin/account" routerLinkActive="active">{{ auth.user()?.email }}</a>
          <button type="button" class="cms-linkbtn" (click)="auth.logout()">Sign out</button>
        </div>
      </aside>
      <main class="cms-main">
        @if (notice.current(); as n) {
          <div class="cms-notice" [class.cms-notice-error]="n.kind === 'error'" role="status" (click)="notice.clear()">{{ n.text }}</div>
        }
        <router-outlet />
      </main>
    </div>
  `,
})
export class AdminLayout {
  protected readonly auth = inject(AuthService);
  protected readonly notice = inject(NoticeService);
}

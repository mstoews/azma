import { Component, computed, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { filter, map } from 'rxjs';
import { AuthService } from './auth.service';
import { Icon, IconName } from '../shared/icon';
import { NoticeService } from './shared/notice.service';
import { ThemeService } from '../shared/theme.service';

interface NavItem { path: string; label: string; icon: IconName; exact?: boolean }

const NAV: { group: string; items: NavItem[] }[] = [
  { group: 'Content', items: [
    { path: '/admin', label: 'Dashboard', icon: 'dashboard', exact: true },
    { path: '/admin/pages', label: 'Pages', icon: 'page' },
    { path: '/admin/profiles', label: 'Team profiles', icon: 'users' },
    { path: '/admin/media', label: 'Media', icon: 'image' },
    { path: '/admin/navigation', label: 'Menu', icon: 'menu' },
  ] },
  { group: 'System', items: [
    { path: '/admin/settings', label: 'Site settings', icon: 'settings' },
    { path: '/admin/users', label: 'Administrators', icon: 'shield' },
    { path: '/admin/activity', label: 'Activity', icon: 'activity' },
  ] },
];

const THEME_LABEL = { system: 'System theme', light: 'Light theme', dark: 'Dark theme' } as const;
const THEME_ICON = { system: 'monitor', light: 'sun', dark: 'moon' } as const;

@Component({
  selector: 'cms-admin-layout',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, Icon],
  template: `
    <div class="cms" [class.cms-collapsed]="theme.collapsed()" [class.cms-drawer-open]="drawer()" translate="no">
      <div class="cms-scrim" (click)="drawer.set(false)"></div>
      <aside class="cms-sidebar" aria-label="Admin">
        <div class="cms-sidebar-top">
          <a routerLink="/admin" class="cms-brand" (click)="drawer.set(false)">
            <span class="cms-logo">A</span><span class="cms-brand-text">AZMA <span>CMS</span></span>
          </a>
          <button type="button" class="cms-iconbtn cms-drawer-close" (click)="drawer.set(false)" aria-label="Close menu">
            <cms-icon name="close" />
          </button>
        </div>
        <nav>
          @for (g of nav; track g.group) {
            <div class="cms-nav-group">{{ g.group }}</div>
            @for (n of g.items; track n.path) {
              <a [routerLink]="n.path" routerLinkActive="active" [routerLinkActiveOptions]="{ exact: !!n.exact }"
                 [attr.title]="theme.collapsed() ? n.label : null" (click)="drawer.set(false)">
                <cms-icon [name]="n.icon" /><span>{{ n.label }}</span>
              </a>
            }
          }
        </nav>
        <div class="cms-sidebar-foot">
          <a routerLink="/admin/account" routerLinkActive="active" class="cms-user" (click)="drawer.set(false)"
             [attr.title]="auth.user()?.email">
            <span class="cms-avatar">{{ initials() }}</span>
            <span class="cms-user-text"><strong>{{ auth.user()?.name || 'Account' }}</strong><small>{{ auth.user()?.email }}</small></span>
          </a>
          <button type="button" class="cms-navbtn" (click)="auth.logout()" [attr.title]="theme.collapsed() ? 'Sign out' : null">
            <cms-icon name="logout" /><span>Sign out</span>
          </button>
        </div>
      </aside>

      <div class="cms-shell">
        <header class="cms-topbar">
          <button type="button" class="cms-iconbtn cms-drawer-toggle" (click)="drawer.set(true)" aria-label="Open menu">
            <cms-icon name="hamburger" />
          </button>
          <button type="button" class="cms-iconbtn cms-collapse-toggle" (click)="theme.collapsed.set(!theme.collapsed())"
                  [attr.aria-label]="theme.collapsed() ? 'Expand sidebar' : 'Collapse sidebar'"
                  [attr.aria-pressed]="theme.collapsed()">
            <cms-icon name="panel" />
          </button>
          <div class="cms-crumbs">
            <span class="cms-muted">AZMA CMS</span><span class="cms-crumb-sep">/</span><strong>{{ section() }}</strong>
          </div>
          <div class="cms-topbar-actions">
            <button type="button" class="cms-iconbtn" (click)="theme.cycle()"
                    [attr.aria-label]="themeLabel()" [attr.title]="themeLabel()">
              <cms-icon [name]="themeIcon()" />
            </button>
            <a href="/" target="_blank" rel="noopener" class="cms-btn cms-btn-ghost cms-btn-sm">
              <cms-icon name="external" /><span class="cms-hide-sm">View site</span>
            </a>
          </div>
        </header>
        <main class="cms-main">
          @if (notice.current(); as n) {
            <div class="cms-notice" [class.cms-notice-error]="n.kind === 'error'" role="status" (click)="notice.clear()">{{ n.text }}</div>
          }
          <router-outlet />
        </main>
      </div>
    </div>
  `,
})
export class AdminLayout {
  protected readonly auth = inject(AuthService);
  protected readonly notice = inject(NoticeService);
  protected readonly theme = inject(ThemeService);
  protected readonly nav = NAV;
  protected readonly drawer = signal(false);

  private readonly url = toSignal(
    inject(Router).events.pipe(filter((e) => e instanceof NavigationEnd), map((e) => e.urlAfterRedirects)),
    { initialValue: inject(Router).url },
  );

  protected readonly section = computed(() => {
    const path = this.url().split(/[?#]/)[0];
    const items = NAV.flatMap((g) => g.items);
    const hit = items.filter((n) => (n.exact ? path === n.path : path === n.path || path.startsWith(n.path + '/')))
      .sort((a, b) => b.path.length - a.path.length)[0];
    return path.startsWith('/admin/account') ? 'Account' : hit?.label ?? 'Dashboard';
  });

  protected readonly initials = computed(() => {
    const u = this.auth.user();
    const src = (u?.name || u?.email || '?').trim();
    const parts = src.split(/[\s@._-]+/).filter(Boolean);
    return ((parts[0]?.[0] ?? '?') + (parts[1]?.[0] ?? '')).toUpperCase();
  });

  protected readonly themeLabel = computed(() => `${THEME_LABEL[this.theme.theme()]} (click to change)`);
  protected readonly themeIcon = computed<IconName>(() => THEME_ICON[this.theme.theme()]);
}

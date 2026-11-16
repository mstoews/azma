import { DOCUMENT } from '@angular/common';
import { Component, ElementRef, HostListener, computed, effect, inject, signal, viewChild } from '@angular/core';
import { NavigationEnd, NavigationStart, Router, RouterLink, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { SiteContentService } from './content.service';
import { PageStateService } from './page-state';
import { Icon, IconName } from './shared/icon';
import { ThemeService } from './shared/theme.service';

const isAdminUrl = (url: string) => /^\/admin(\/|\?|#|$)/.test(url);

const THEME_LABEL = { system: 'System theme', light: 'Light theme', dark: 'Dark theme' } as const;
const THEME_ICON = { system: 'monitor', light: 'sun', dark: 'moon' } as const;

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, Icon],
  templateUrl: './app.html',
})
export class App {
  private readonly doc = inject(DOCUMENT);
  private readonly pageState = inject(PageStateService);
  private readonly content = inject(SiteContentService);
  private readonly router = inject(Router);
  protected readonly theme = inject(ThemeService);

  protected readonly settings = this.content.settings;
  protected readonly nav = this.content.nav;
  protected readonly state = this.pageState.state;
  protected readonly menuOpen = this.pageState.menuOpen;
  protected readonly year = new Date().getFullYear();

  /** Internal menu links and external ones (e.g. the Japanese site) are shown apart. */
  protected readonly internalNav = computed(() => this.nav().filter((n) => n.link));
  protected readonly externalNav = computed(() => this.nav().filter((n) => !n.link && n.href));

  /**
   * The admin area renders without the site chrome. Switched on
   * NavigationStart (not End) so the admin outlet exists before the admin
   * component is activated into it.
   */
  protected readonly isAdmin = signal(isAdminUrl(this.doc.location?.pathname ?? ''));

  /** The header gets a border and shadow once the page has scrolled. */
  protected readonly scrolled = signal(false);

  protected readonly themeLabel = computed(() => `${THEME_LABEL[this.theme.theme()]} (click to change)`);
  protected readonly themeIcon = computed<IconName>(() => THEME_ICON[this.theme.theme()]);

  private readonly menuToggle = viewChild<ElementRef<HTMLButtonElement>>('menuToggle');
  private readonly menuPanel = viewChild<ElementRef<HTMLElement>>('menuPanel');

  constructor() {
    const body = this.doc.body;
    effect(() => {
      body.className = this.isAdmin() ? 'cms-admin-body' : 'site-body';
      body.classList.toggle('site-scroll-locked', this.menuOpen());
    });

    this.router.events
      .pipe(filter((e) => e instanceof NavigationStart))
      .subscribe((e) => this.isAdmin.set(isAdminUrl(e.url)));

    // Close the menu whenever the route changes.
    this.router.events
      .pipe(filter((e) => e instanceof NavigationEnd))
      .subscribe(() => this.menuOpen.set(false));
  }

  /** Marks Japanese menu labels (e.g. the link to the Japanese site) for screen readers. */
  protected langOf(label: string): string | null {
    return /[\u3040-\u30ff\u3400-\u9fff]/.test(label) ? 'ja' : null;
  }

  protected isCurrent(pageId: number | undefined): boolean {
    const s = this.state();
    return s.kind === 'page' && pageId !== undefined && s.id === pageId;
  }

  protected openMenu(): void {
    this.menuOpen.set(true);
    setTimeout(() => this.menuPanel()?.nativeElement.querySelector<HTMLElement>('a, button')?.focus());
  }

  protected closeMenu(): void {
    if (!this.menuOpen()) return;
    this.menuOpen.set(false);
    this.menuToggle()?.nativeElement.focus();
  }

  /** Keep Tab inside the open menu. */
  protected trapFocus(e: KeyboardEvent): void {
    if (e.key !== 'Tab') return;
    const items = this.menuPanel()?.nativeElement.querySelectorAll<HTMLElement>('a, button');
    if (!items?.length) return;
    const first = items[0], last = items[items.length - 1];
    if (e.shiftKey && this.doc.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && this.doc.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  protected skipTo(id: string, event: Event): void {
    event.preventDefault();
    const el = this.doc.getElementById(id);
    el?.focus();
    el?.scrollIntoView();
  }

  @HostListener('window:scroll')
  protected onScroll(): void {
    this.scrolled.set((this.doc.defaultView?.scrollY ?? 0) > 8);
  }

  @HostListener('document:keyup.escape')
  protected onEscape(): void {
    this.closeMenu();
  }
}

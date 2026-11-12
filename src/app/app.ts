import { DOCUMENT } from '@angular/common';
import { Component, ElementRef, HostListener, computed, effect, inject, signal, viewChild } from '@angular/core';
import { NavigationEnd, NavigationStart, Router, RouterLink, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { SiteContentService } from './content.service';
import { PageStateService } from './page-state';

const isAdminUrl = (url: string) => /^\/admin(\/|\?|#|$)/.test(url);

const COMMON_BODY = 'wp-custom-logo wp-theme-cobber-pro booster-extension';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink],
  templateUrl: './app.html',
})
export class App {
  private readonly doc = inject(DOCUMENT);
  private readonly pageState = inject(PageStateService);

  private readonly content = inject(SiteContentService);
  private readonly router = inject(Router);

  protected readonly settings = this.content.settings;
  protected readonly nav = this.content.nav;

  /**
   * The admin area renders without the theme chrome. Switched on
   * NavigationStart (not End) so the admin outlet exists before the admin
   * component is activated into it.
   */
  protected readonly isAdmin = signal(isAdminUrl(this.doc.location?.pathname ?? ''));
  protected readonly year = new Date().getFullYear();

  protected readonly state = this.pageState.state;
  protected readonly offcanvasOpen = this.pageState.offcanvasOpen;
  protected readonly isHome = computed(() => this.state().kind === 'home');

  private readonly menuToggle = viewChild<ElementRef<HTMLButtonElement>>('menuToggle');
  private readonly menuClose = viewChild<ElementRef<HTMLButtonElement>>('menuClose');
  private readonly offcanvas = viewChild<ElementRef<HTMLElement>>('offcanvas');

  private readonly bodyClass = computed(() => {
    if (this.isAdmin()) return 'cms-admin-body';
    const s = this.state();
    switch (s.kind) {
      case 'post':
        return `wp-singular post-template-default single single-post postid-${s.cssId} single-format-standard ${COMMON_BODY} hide-comment-rating site-layout-default`;
      case 'page':
        return `wp-singular page-template-default page page-id-${s.cssId} ${COMMON_BODY} site-layout-default`;
      default:
        return `home blog ${COMMON_BODY} hfeed site-layout-default`;
    }
  });

  constructor() {
    const body = this.doc.body;
    effect(() => {
      const loaded = body.classList.contains('page-loaded');
      body.className = this.bodyClass();
      if (loaded) body.classList.add('page-loaded');
      body.classList.toggle('body-scroll-locked', this.offcanvasOpen());
    });

    // Preloader: the theme fades it out once the window has finished loading.
    const markLoaded = () => body.classList.add('page-loaded');
    if (this.doc.readyState === 'complete') markLoaded();
    else this.doc.defaultView?.addEventListener('load', markLoaded, { once: true });

    this.router.events
      .pipe(filter((e) => e instanceof NavigationStart))
      .subscribe((e) => this.isAdmin.set(isAdminUrl(e.url)));

    // Close the menu whenever the route changes.
    this.router.events
      .pipe(filter((e) => e instanceof NavigationEnd))
      .subscribe(() => this.offcanvasOpen.set(false));
  }

  protected openMenu(): void {
    this.offcanvasOpen.set(true);
    setTimeout(() => this.menuClose()?.nativeElement.focus());
  }

  protected closeMenu(): void {
    if (!this.offcanvasOpen()) return;
    this.offcanvasOpen.set(false);
    setTimeout(() => this.menuToggle()?.nativeElement.focus(), 300);
  }

  /** Focus-trap sentinels inside the off-canvas menu (mirrors the theme's behaviour). */
  protected focusLastMenuItem(): void {
    const links = this.offcanvas()?.nativeElement.querySelectorAll<HTMLAnchorElement>('#primary-nav-offcanvas a');
    links?.[links.length - 1]?.focus();
  }

  protected focusCloseButton(): void {
    this.menuClose()?.nativeElement.focus();
  }

  protected scrollTo(id: string, event: Event): void {
    event.preventDefault();
    this.doc.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  }

  @HostListener('document:keyup.escape')
  protected onEscape(): void {
    this.closeMenu();
  }
}

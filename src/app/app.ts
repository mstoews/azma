import { DOCUMENT } from '@angular/common';
import { Component, ElementRef, HostListener, computed, effect, inject, viewChild } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { PageStateService } from './page-state';
import { HOME_DESCRIPTION, LOGO, NAV, SITE_NAME, SITE_TAGLINE } from './site-data';

const COMMON_BODY = 'wp-custom-logo wp-theme-cobber-pro booster-extension';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink],
  templateUrl: './app.html',
})
export class App {
  private readonly doc = inject(DOCUMENT);
  private readonly pageState = inject(PageStateService);

  protected readonly siteName = SITE_NAME;
  protected readonly tagline = SITE_TAGLINE;
  protected readonly homeDescription = HOME_DESCRIPTION;
  protected readonly logo = LOGO;
  protected readonly nav = NAV;
  protected readonly year = new Date().getFullYear();

  protected readonly state = this.pageState.state;
  protected readonly offcanvasOpen = this.pageState.offcanvasOpen;
  protected readonly isHome = computed(() => this.state().kind === 'home');

  private readonly menuToggle = viewChild<ElementRef<HTMLButtonElement>>('menuToggle');
  private readonly menuClose = viewChild<ElementRef<HTMLButtonElement>>('menuClose');
  private readonly offcanvas = viewChild<ElementRef<HTMLElement>>('offcanvas');

  private readonly bodyClass = computed(() => {
    const s = this.state();
    switch (s.kind) {
      case 'post':
        return `wp-singular post-template-default single single-post postid-${s.id} single-format-standard ${COMMON_BODY} hide-comment-rating site-layout-default`;
      case 'page':
        return `wp-singular page-template-default page page-id-${s.id} ${COMMON_BODY} site-layout-default`;
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

    // Close the menu whenever the route changes.
    inject(Router)
      .events.pipe(filter((e) => e instanceof NavigationEnd))
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

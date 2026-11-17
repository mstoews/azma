import { DOCUMENT } from '@angular/common';
import { Injectable, computed, inject, signal } from '@angular/core';

/** Google Analytics 4 measurement id (was hard-coded in index.html). */
export const GA_MEASUREMENT_ID = 'G-Q5P8ZM0VN7';

export type ConsentChoice = 'granted' | 'denied';

const KEY = 'azma.consent.analytics';

type GtagWindow = Window & { dataLayer?: unknown[]; gtag?: (...args: unknown[]) => void } & Record<string, unknown>;

/** Global Privacy Control (https://globalprivacycontrol.org): not yet in the DOM typings. */
type GpcNavigator = Navigator & { globalPrivacyControl?: boolean };

/**
 * Visitor consent for analytics. Google Analytics is not loaded, and sets no
 * cookies, until the visitor accepts. The choice is remembered in
 * localStorage and can be changed from the footer ("Cookie settings").
 *
 * A browser sending Global Privacy Control counts as a decline: no banner,
 * Analytics never loads, and that overrides an earlier "accept" (which is
 * kept, so it applies again if the visitor turns GPC off).
 */
@Injectable({ providedIn: 'root' })
export class ConsentService {
  private readonly doc = inject(DOCUMENT);
  private readonly win = this.doc.defaultView as GtagWindow | null;

  /** True when the browser sends Global Privacy Control. */
  readonly gpc = signal((this.win?.navigator as GpcNavigator | undefined)?.globalPrivacyControl === true);

  /** The stored choice, or null when the visitor has not answered yet. */
  readonly choice = signal<ConsentChoice | null>(this.read());

  /** What applies on this page: GPC turns any stored choice into a decline. */
  readonly effective = computed<ConsentChoice | null>(() => (this.gpc() ? 'denied' : this.choice()));

  /** True while the banner should be shown: no answer yet (and no GPC), or reopened from the footer. */
  private readonly reopened = signal(false);
  readonly bannerOpen = computed(() => this.effective() === null || this.reopened());

  private loaded = false;

  /** Loads Analytics if the visitor already accepted on an earlier visit (and GPC is off). */
  init(): void {
    if (this.gpc()) {
      // Analytics may have run on an earlier visit, before GPC was turned on.
      this.deleteAnalyticsCookies();
      return;
    }
    if (this.choice() === 'granted') this.loadAnalytics();
  }

  accept(): void {
    if (this.gpc()) return; // GPC is an opt-out the page can't override.
    this.save('granted');
    this.reopened.set(false);
    this.loadAnalytics();
  }

  decline(): void {
    const wasLoaded = this.loaded;
    this.save('denied');
    this.reopened.set(false);
    if (wasLoaded) this.revoke();
  }

  /** Shows the banner again so the visitor can change their mind. */
  reopen(): void {
    this.reopened.set(true);
  }

  /** Closes a reopened banner without changing the stored choice. */
  dismiss(): void {
    if (this.effective() !== null) this.reopened.set(false);
  }

  private loadAnalytics(): void {
    const w = this.win;
    if (this.loaded || !w || this.gpc()) return;
    this.loaded = true;
    delete w[`ga-disable-${GA_MEASUREMENT_ID}`];
    w.dataLayer = w.dataLayer ?? [];
    // gtag.js expects the Arguments object itself, not an array.
    w.gtag = function gtag() {
      // eslint-disable-next-line prefer-rest-params
      w.dataLayer!.push(arguments);
    };
    w.gtag('js', new Date());
    w.gtag('config', GA_MEASUREMENT_ID);
    const s = this.doc.createElement('script');
    s.async = true;
    s.src = `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`;
    s.dataset['consent'] = 'analytics';
    this.doc.head.appendChild(s);
  }

  /**
   * Turning consent off after Analytics has loaded: stop it sending, delete
   * its cookies, and reload so the script is gone from the page.
   */
  private revoke(): void {
    const w = this.win;
    if (!w) return;
    w[`ga-disable-${GA_MEASUREMENT_ID}`] = true;
    this.deleteAnalyticsCookies();
    w.location.reload();
  }

  /** Removes Google Analytics cookies (_ga, _ga_<id>, _gid) on this host and its parent domain. */
  private deleteAnalyticsCookies(): void {
    const w = this.win;
    if (!w) return;
    const host = w.location.hostname;
    const domains = ['', host, '.' + host, '.' + host.split('.').slice(-2).join('.')];
    for (const name of this.doc.cookie.split(';').map((c) => c.split('=')[0].trim())) {
      if (name !== '_ga' && !name.startsWith('_ga_') && name !== '_gid') continue;
      for (const d of domains) {
        this.doc.cookie = `${name}=; Max-Age=0; path=/${d ? '; domain=' + d : ''}`;
      }
    }
  }

  private read(): ConsentChoice | null {
    try {
      const v = localStorage.getItem(KEY);
      return v === 'granted' || v === 'denied' ? v : null;
    } catch {
      return null;
    }
  }

  private save(choice: ConsentChoice): void {
    this.choice.set(choice);
    try {
      localStorage.setItem(KEY, choice);
    } catch {
      /* storage blocked: the choice lasts for this page only */
    }
  }
}

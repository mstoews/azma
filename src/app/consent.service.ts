import { DOCUMENT } from '@angular/common';
import { Injectable, computed, inject, signal } from '@angular/core';

/** Google Analytics 4 measurement id (was hard-coded in index.html). */
export const GA_MEASUREMENT_ID = 'G-Q5P8ZM0VN7';

export type ConsentChoice = 'granted' | 'denied';

const KEY = 'azma.consent.analytics';

type GtagWindow = Window & { dataLayer?: unknown[]; gtag?: (...args: unknown[]) => void } & Record<string, unknown>;

/**
 * Visitor consent for analytics. Google Analytics is not loaded, and sets no
 * cookies, until the visitor accepts. The choice is remembered in
 * localStorage and can be changed from the footer ("Cookie settings").
 */
@Injectable({ providedIn: 'root' })
export class ConsentService {
  private readonly doc = inject(DOCUMENT);
  private readonly win = this.doc.defaultView as GtagWindow | null;

  /** The stored choice, or null when the visitor has not answered yet. */
  readonly choice = signal<ConsentChoice | null>(this.read());
  /** True while the banner should be shown: no answer yet, or reopened from the footer. */
  private readonly reopened = signal(false);
  readonly bannerOpen = computed(() => this.choice() === null || this.reopened());

  private loaded = false;

  /** Loads Analytics if the visitor already accepted on an earlier visit. */
  init(): void {
    if (this.choice() === 'granted') this.loadAnalytics();
  }

  accept(): void {
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
    if (this.choice() !== null) this.reopened.set(false);
  }

  private loadAnalytics(): void {
    const w = this.win;
    if (this.loaded || !w) return;
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
    const host = w.location.hostname;
    const domains = ['', host, '.' + host, '.' + host.split('.').slice(-2).join('.')];
    for (const name of this.doc.cookie.split(';').map((c) => c.split('=')[0].trim())) {
      if (name !== '_ga' && !name.startsWith('_ga_') && name !== '_gid') continue;
      for (const d of domains) {
        this.doc.cookie = `${name}=; Max-Age=0; path=/${d ? '; domain=' + d : ''}`;
      }
    }
    w.location.reload();
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

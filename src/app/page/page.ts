import { Component, computed, effect, inject, input } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { PageStateService } from '../page-state';
import { PAGES, SITE_NAME } from '../site-data';
import { TrustedHtmlPipe } from '../trusted-html';

@Component({
  selector: 'app-page',
  imports: [TrustedHtmlPipe],
  templateUrl: './page.html',
})
export class PageDetail {
  /** Bound from the route's `data.slug`. */
  readonly slug = input.required<string>();
  protected readonly page = computed(() => PAGES.find((p) => p.slug === this.slug())!);

  constructor() {
    const pageState = inject(PageStateService);
    const title = inject(Title);
    effect(() => {
      const p = this.page();
      pageState.state.set({ kind: 'page', id: p.id, image: p.hero, imageAlt: p.title });
      title.setTitle(`${p.title} – ${SITE_NAME}`);
    });
  }
}

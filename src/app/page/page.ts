import { Component, computed, effect, inject, input } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { Router, RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { PageStateService } from '../page-state';
import { Icon } from '../shared/icon';
import { excerpt, firstEmail } from '../site-helpers';
import { TrustedHtmlPipe } from '../trusted-html';

@Component({
  selector: 'app-page',
  imports: [TrustedHtmlPipe, RouterLink, Icon],
  templateUrl: './page.html',
})
export class PageDetail {
  /** Bound from the `:slug` route parameter. */
  readonly slug = input.required<string>();
  private readonly content = inject(SiteContentService);
  protected readonly page = computed(() => this.content.pages().find((p) => p.slug === this.slug()));

  /** The other menu pages, for the "More about us" list. */
  protected readonly others = computed(() => {
    const pages = this.content.pages();
    return this.content.nav()
      .filter((n) => n.link && n.link !== '/' + this.slug())
      .map((n) => ({ label: n.label, page: pages.find((p) => '/' + p.slug === n.link) }))
      .filter((x) => !!x.page)
      .map((x) => ({ label: x.label, slug: x.page!.slug, summary: excerpt(x.page!.content, 80) }));
  });

  /** Contact address for the side card: from the Contact page, or this page. */
  protected readonly email = computed(() => {
    const contact = this.content.pages().find((p) => p.slug === 'contact');
    return firstEmail(contact?.content ?? '') ?? firstEmail(this.page()?.content ?? '');
  });
  protected readonly isContact = computed(() => this.slug() === 'contact');

  constructor() {
    const pageState = inject(PageStateService);
    const title = inject(Title);
    const router = inject(Router);
    effect(() => {
      const p = this.page();
      if (!p) {
        router.navigateByUrl('/');
        return;
      }
      pageState.state.set({ kind: 'page', id: p.id });
      title.setTitle(`${p.title} – ${this.content.settings().siteName}`);
    });
  }
}

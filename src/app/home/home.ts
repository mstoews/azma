import { Component, computed, effect, inject, signal } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { PageStateService } from '../page-state';
import { Icon } from '../shared/icon';
import { excerpt, profileLines } from '../site-helpers';

@Component({
  selector: 'app-home',
  imports: [RouterLink, Icon],
  templateUrl: './home.html',
})
export class Home {
  private readonly content = inject(SiteContentService);
  protected readonly settings = this.content.settings;

  protected readonly team = computed(() => this.content.profiles().map((p) => ({ ...p, ...profileLines(p) })));

  /** Offices in the order they first appear (the CMS order puts the leads first). */
  protected readonly offices = computed(() => {
    const counts = new Map<string, number>();
    for (const m of this.team()) if (m.office) counts.set(m.office, (counts.get(m.office) ?? 0) + 1);
    return [...counts].map(([name, count]) => ({ name, count }));
  });

  protected readonly officeNames = computed(() => this.offices().map((o) => o.name).join(' · '));

  protected readonly office = signal<string | null>(null);
  protected readonly visibleTeam = computed(() => {
    const o = this.office();
    return o ? this.team().filter((m) => m.office === o) : this.team();
  });

  /** Pages linked from the menu, in menu order, as "about us" cards. */
  protected readonly sections = computed(() => {
    const pages = this.content.pages();
    return this.content.nav()
      .filter((n) => n.link)
      .map((n) => pages.find((p) => '/' + p.slug === n.link))
      .filter((p) => !!p)
      .map((p) => ({ ...p, label: this.content.nav().find((n) => n.link === '/' + p.slug)?.label ?? p.title, summary: excerpt(p.content, 130) }));
  });

  protected readonly contactLink = computed(() => {
    const p = this.content.pages().find((x) => x.slug === 'contact');
    return p ? '/' + p.slug : null;
  });

  constructor() {
    const pageState = inject(PageStateService);
    const title = inject(Title);
    effect(() => {
      const s = this.settings();
      pageState.state.set({ kind: 'home' });
      title.setTitle(`${s.siteName} – ${s.tagline}`);
    });
  }
}

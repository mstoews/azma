import { Component, computed, effect, inject, input } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { Router, RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { PageStateService } from '../page-state';
import { Icon } from '../shared/icon';
import { firstEmail, profileLines, withoutRepeatedHeading } from '../site-helpers';
import { TrustedHtmlPipe } from '../trusted-html';

@Component({
  selector: 'app-profile',
  imports: [TrustedHtmlPipe, RouterLink, Icon],
  templateUrl: './profile.html',
})
export class ProfileDetail {
  readonly slug = input.required<string>();
  private readonly content = inject(SiteContentService);

  private readonly index = computed(() => this.content.profiles().findIndex((p) => p.slug === this.slug()));
  protected readonly profile = computed(() => this.content.profiles()[this.index()]);
  protected readonly lines = computed(() => (this.profile() ? profileLines(this.profile()) : null));
  protected readonly body = computed(() => (this.profile() ? withoutRepeatedHeading(this.profile()) : ''));

  /** Neighbours in team order, wrapping around. */
  protected readonly prev = computed(() => this.neighbour(-1));
  protected readonly next = computed(() => this.neighbour(1));

  /** Email link to the firm (from the Contact page), with the consultant's name as the subject. */
  protected readonly mailto = computed(() => {
    const e = firstEmail(this.content.pages().find((p) => p.slug === 'contact')?.content ?? '');
    const p = this.profile();
    return e && p ? `mailto:${e}?subject=${encodeURIComponent('Enquiry for ' + p.title)}` : null;
  });

  constructor() {
    const pageState = inject(PageStateService);
    const title = inject(Title);
    const router = inject(Router);
    effect(() => {
      const p = this.profile();
      if (!p) {
        router.navigateByUrl('/');
        return;
      }
      pageState.state.set({ kind: 'profile', id: p.id });
      title.setTitle(`${p.title} – ${this.content.settings().siteName}`);
    });
  }

  private neighbour(d: number) {
    const all = this.content.profiles();
    if (all.length < 2 || this.index() < 0) return null;
    const p = all[(this.index() + d + all.length) % all.length];
    return { ...p, ...profileLines(p) };
  }
}

import { Component, computed, effect, inject, input } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { Router } from '@angular/router';
import { SiteContentService } from '../content.service';
import { PageStateService } from '../page-state';
import { cssId } from '../site-data';
import { TrustedHtmlPipe } from '../trusted-html';

@Component({
  selector: 'app-profile',
  imports: [TrustedHtmlPipe],
  templateUrl: './profile.html',
})
export class ProfileDetail {
  readonly slug = input.required<string>();
  private readonly content = inject(SiteContentService);
  protected readonly profile = computed(() => this.content.profiles().find((p) => p.slug === this.slug()));
  protected readonly cssId = cssId;

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
      pageState.state.set({ kind: 'post', id: p.id, cssId: cssId(p), image: p.hero, imageAlt: p.title });
      title.setTitle(`${p.title} – ${this.content.settings().siteName}`);
    });
  }
}

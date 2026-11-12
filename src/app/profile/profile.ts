import { Component, computed, effect, inject, input } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { Router } from '@angular/router';
import { PageStateService } from '../page-state';
import { PROFILES, SITE_NAME } from '../site-data';
import { TrustedHtmlPipe } from '../trusted-html';

@Component({
  selector: 'app-profile',
  imports: [TrustedHtmlPipe],
  templateUrl: './profile.html',
})
export class ProfileDetail {
  readonly slug = input.required<string>();
  protected readonly profile = computed(() => PROFILES.find((p) => p.slug === this.slug()));

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
      pageState.state.set({ kind: 'post', id: p.id, image: p.hero, imageAlt: p.title });
      title.setTitle(`${p.title} – ${SITE_NAME}`);
    });
  }
}

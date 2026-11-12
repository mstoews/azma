import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SiteContentService } from './content.service';

/** Keeps old WordPress links (`/?p=1`, `/?page_id=176`) working. */
export const legacyWordPressUrls: CanActivateFn = (route) => {
  const router = inject(Router);
  const content = inject(SiteContentService);
  const p = Number(route.queryParamMap.get('p'));
  const pageId = Number(route.queryParamMap.get('page_id'));
  if (p) {
    const profile = content.profiles().find((x) => x.legacyId === p);
    if (profile) return router.parseUrl('/profile/' + profile.slug);
  }
  if (pageId) {
    // 467 was the Japanese-site link in the WordPress menu.
    if (pageId === 467) {
      window.location.href = 'https://azma-associates.jp/';
      return false;
    }
    const page = content.pages().find((x) => x.legacyId === pageId);
    if (page) return router.parseUrl('/' + page.slug);
  }
  return true;
};

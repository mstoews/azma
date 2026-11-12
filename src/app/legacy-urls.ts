import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { PAGES, PROFILES } from './site-data';

/** Keeps old WordPress links (`/?p=1`, `/?page_id=176`) working. */
export const legacyWordPressUrls: CanActivateFn = (route) => {
  const router = inject(Router);
  const p = Number(route.queryParamMap.get('p'));
  const pageId = Number(route.queryParamMap.get('page_id'));
  if (p) {
    const profile = PROFILES.find((x) => x.id === p);
    if (profile) return router.parseUrl('/profile/' + profile.slug);
  }
  if (pageId) {
    if (pageId === 467) {
      window.location.href = 'https://azma-associates.jp/';
      return false;
    }
    const page = PAGES.find((x) => x.id === pageId);
    if (page) return router.parseUrl('/' + page.slug);
  }
  return true;
};

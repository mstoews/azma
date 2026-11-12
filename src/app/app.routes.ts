import { Routes } from '@angular/router';
import { Home } from './home/home';
import { ProfileDetail } from './profile/profile';
import { PageDetail } from './page/page';
import { legacyWordPressUrls } from './legacy-urls';
import { PAGES } from './site-data';

export const routes: Routes = [
  { path: '', pathMatch: 'full', component: Home, canActivate: [legacyWordPressUrls] },
  { path: 'profile/:slug', component: ProfileDetail },
  ...PAGES.map((p) => ({ path: p.slug, component: PageDetail, data: { slug: p.slug } })),
  { path: '**', redirectTo: '' },
];

import { Routes } from '@angular/router';
import { Home } from './home/home';
import { ProfileDetail } from './profile/profile';
import { PageDetail } from './page/page';
import { legacyWordPressUrls } from './legacy-urls';

export const routes: Routes = [
  { path: '', pathMatch: 'full', component: Home, canActivate: [legacyWordPressUrls] },
  { path: 'admin', loadChildren: () => import('./admin/admin.routes').then((m) => m.ADMIN_ROUTES) },
  { path: 'profile/:slug', component: ProfileDetail },
  // Pages are managed in the CMS, so their slugs are not known at build time.
  { path: ':slug', component: PageDetail },
  { path: '**', redirectTo: '' },
];

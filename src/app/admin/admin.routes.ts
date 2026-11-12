import { Routes } from '@angular/router';
import { Account } from './account';
import { Activity } from './activity';
import { AdminLayout } from './admin-layout';
import { adminGuard } from './auth.guard';
import { ContentEdit, unsavedChangesGuard } from './content-edit';
import { ContentList } from './content-list';
import { Dashboard } from './dashboard';
import { Login } from './login';
import { MediaLibrary } from './media-library';
import { NavEditor } from './nav-editor';
import { Settings } from './settings';
import { Users } from './users';

export const ADMIN_ROUTES: Routes = [
  { path: 'login', component: Login },
  {
    path: '',
    component: AdminLayout,
    canActivate: [adminGuard],
    canActivateChild: [adminGuard],
    children: [
      { path: '', component: Dashboard },
      { path: 'pages', component: ContentList, data: { kind: 'page' } },
      { path: 'pages/new', component: ContentEdit, data: { kind: 'page' }, canDeactivate: [unsavedChangesGuard] },
      { path: 'pages/:id', component: ContentEdit, data: { kind: 'page' }, canDeactivate: [unsavedChangesGuard] },
      { path: 'profiles', component: ContentList, data: { kind: 'profile' } },
      { path: 'profiles/new', component: ContentEdit, data: { kind: 'profile' }, canDeactivate: [unsavedChangesGuard] },
      { path: 'profiles/:id', component: ContentEdit, data: { kind: 'profile' }, canDeactivate: [unsavedChangesGuard] },
      { path: 'navigation', component: NavEditor },
      { path: 'media', component: MediaLibrary },
      { path: 'settings', component: Settings },
      { path: 'users', component: Users },
      { path: 'activity', component: Activity },
      { path: 'account', component: Account },
    ],
  },
];

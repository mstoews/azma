import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import {
  AdminNavItem, AdminPage, AdminProfile, AdminSettings, AdminUser, AuditEntry, MediaItem, PageInput, ProfileInput,
} from './models';

const BASE = '/api/v1/admin';

/** Thin promise-based client for the admin API. */
@Injectable({ providedIn: 'root' })
export class AdminApi {
  private readonly http = inject(HttpClient);

  private get<T>(path: string) { return firstValueFrom(this.http.get<T>(BASE + path)); }
  private post<T>(path: string, body: unknown) { return firstValueFrom(this.http.post<T>(BASE + path, body)); }
  private put<T>(path: string, body: unknown) { return firstValueFrom(this.http.put<T>(BASE + path, body)); }
  private patch<T>(path: string, body: unknown) { return firstValueFrom(this.http.patch<T>(BASE + path, body)); }
  private del(path: string) { return firstValueFrom(this.http.delete<void>(BASE + path)); }

  pages() { return this.get<AdminPage[]>('/pages'); }
  page(id: number) { return this.get<AdminPage>(`/pages/${id}`); }
  createPage(p: PageInput) { return this.post<AdminPage>('/pages', p); }
  updatePage(id: number, p: PageInput) { return this.put<AdminPage>(`/pages/${id}`, p); }
  deletePage(id: number) { return this.del(`/pages/${id}`); }
  reorderPages(ids: number[]) { return this.put<void>('/pages/order', { ids }); }

  profiles() { return this.get<AdminProfile[]>('/profiles'); }
  profile(id: number) { return this.get<AdminProfile>(`/profiles/${id}`); }
  createProfile(p: ProfileInput) { return this.post<AdminProfile>('/profiles', p); }
  updateProfile(id: number, p: ProfileInput) { return this.put<AdminProfile>(`/profiles/${id}`, p); }
  deleteProfile(id: number) { return this.del(`/profiles/${id}`); }
  reorderProfiles(ids: number[]) { return this.put<void>('/profiles/order', { ids }); }

  nav() { return this.get<AdminNavItem[]>('/nav'); }
  saveNav(items: Pick<AdminNavItem, 'label' | 'pageId' | 'href'>[]) {
    return this.put<AdminNavItem[]>('/nav', {
      items: items.map((i) => (i.pageId ? { label: i.label, pageId: i.pageId } : { label: i.label, href: i.href })),
    });
  }

  settings() { return this.get<AdminSettings>('/settings'); }
  saveSettings(s: AdminSettings) { return this.put<AdminSettings>('/settings', s); }

  media() { return this.get<MediaItem[]>('/media'); }
  uploadMedia(file: File, alt = '') {
    const fd = new FormData();
    fd.append('file', file);
    fd.append('alt', alt);
    return this.post<MediaItem>('/media', fd);
  }
  updateMediaAlt(id: number, alt: string) { return this.patch<MediaItem>(`/media/${id}`, { alt }); }
  deleteMedia(id: number, force = false) { return this.del(`/media/${id}${force ? '?force=1' : ''}`); }

  users() { return this.get<AdminUser[]>('/users'); }
  createUser(u: { email: string; name: string; password: string }) { return this.post<AdminUser>('/users', u); }
  updateUser(id: string, u: { name: string; disabled: boolean }) { return this.put<AdminUser>(`/users/${id}`, u); }
  setUserPassword(id: string, password: string) { return this.put<void>(`/users/${id}/password`, { password }); }
  deleteUser(id: string) { return this.del(`/users/${id}`); }

  audit(limit = 50, offset = 0) { return this.get<AuditEntry[]>(`/audit?limit=${limit}&offset=${offset}`); }

  changeOwnPassword(currentPassword: string, newPassword: string) {
    return firstValueFrom(this.http.put<void>('/api/v1/auth/password', { currentPassword, newPassword }));
  }
}

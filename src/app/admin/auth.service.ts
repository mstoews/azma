import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { AdminUser } from './models';

const TOKEN_KEY = 'azma.cms.token';

function readToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

/** Session state for the admin area. The token is an opaque bearer issued by the CMS. */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);

  readonly token = signal<string | null>(readToken());
  readonly user = signal<AdminUser | null>(null);
  readonly signedIn = computed(() => !!this.token() && !!this.user());

  async login(email: string, password: string): Promise<void> {
    const res = await firstValueFrom(
      this.http.post<{ token: string; user: AdminUser }>('/api/v1/auth/login', { email, password }),
    );
    this.setToken(res.token);
    this.user.set(res.user);
  }

  /** Validates a stored token. Returns false (and clears it) when the session is gone. */
  async restore(): Promise<boolean> {
    if (!this.token()) return false;
    if (this.user()) return true;
    try {
      const res = await firstValueFrom(this.http.get<{ user: AdminUser }>('/api/v1/auth/me'));
      this.user.set(res.user);
      return true;
    } catch {
      this.clear();
      return false;
    }
  }

  async logout(): Promise<void> {
    try {
      await firstValueFrom(this.http.post('/api/v1/auth/logout', {}));
    } catch {
      /* the session may already be gone; sign out locally regardless */
    }
    this.clear();
    await this.router.navigateByUrl('/admin/login');
  }

  /** Called by the interceptor when the API rejects the token. */
  expire(): void {
    if (!this.token()) return;
    this.clear();
    this.router.navigate(['/admin/login'], { queryParams: { expired: 1, next: this.router.url } });
  }

  clear(): void {
    this.setToken(null);
    this.user.set(null);
  }

  private setToken(t: string | null): void {
    this.token.set(t);
    try {
      if (t) localStorage.setItem(TOKEN_KEY, t);
      else localStorage.removeItem(TOKEN_KEY);
    } catch {
      /* storage blocked: the session lasts for this tab only */
    }
  }
}

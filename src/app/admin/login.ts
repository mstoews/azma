import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { ActivatedRoute, Router } from '@angular/router';
import { AuthService } from './auth.service';
import { errorMessage } from './auth.interceptor';

@Component({
  selector: 'cms-login',
  imports: [FormsModule],
  template: `
    <div class="cms cms-login" translate="no">
      <form class="cms-card" (ngSubmit)="submit()">
        <h1>AZMA <span>CMS</span></h1>
        <p class="cms-muted">Administrator sign-in</p>
        @if (expired) { <p class="cms-error">Your session has ended. Please sign in again.</p> }
        @if (error()) { <p class="cms-error" role="alert">{{ error() }}</p> }
        <label class="cms-field">
          <span class="cms-label">Email</span>
          <input type="email" name="email" autocomplete="username" required [(ngModel)]="email" />
        </label>
        <label class="cms-field">
          <span class="cms-label">Password</span>
          <input type="password" name="password" autocomplete="current-password" required [(ngModel)]="password" />
        </label>
        <button class="cms-btn cms-btn-primary" type="submit" [disabled]="busy()">{{ busy() ? 'Signing in…' : 'Sign in' }}</button>
        <a href="/" class="cms-muted">← Back to the site</a>
      </form>
    </div>
  `,
})
export class Login {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected email = '';
  protected password = '';
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  protected readonly expired = !!this.route.snapshot.queryParamMap.get('expired');

  constructor() {
    inject(Title).setTitle('Sign in – AZMA CMS');
  }

  protected async submit(): Promise<void> {
    if (!this.email || !this.password) return;
    this.busy.set(true);
    this.error.set('');
    try {
      await this.auth.login(this.email, this.password);
      const next = this.route.snapshot.queryParamMap.get('next');
      // Only follow same-site admin paths.
      await this.router.navigateByUrl(next && next.startsWith('/admin') ? next : '/admin');
    } catch (e) {
      this.error.set(errorMessage(e));
      this.password = '';
    } finally {
      this.busy.set(false);
    }
  }
}

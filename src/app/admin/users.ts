import { DatePipe } from '@angular/common';
import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { AdminApi } from './admin-api.service';
import { AuthService } from './auth.service';
import { errorMessage } from './auth.interceptor';
import { AdminUser } from './models';
import { NoticeService } from './shared/notice.service';

@Component({
  selector: 'cms-users',
  imports: [FormsModule, DatePipe],
  template: `
    <header class="cms-head"><h1>Administrators</h1></header>
    <p class="cms-muted">Everyone listed here can edit the whole site. Disable an account to revoke access immediately.</p>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <table class="cms-table">
      <thead><tr><th>Email</th><th>Name</th><th>Last sign-in</th><th>Status</th><th></th></tr></thead>
      <tbody>
        @for (u of users(); track u.id) {
          <tr>
            <td>{{ u.email }} @if (u.id === me()) { <span class="cms-badge">you</span> }</td>
            <td>{{ u.name }}</td>
            <td class="cms-muted">{{ u.lastLoginAt ? (u.lastLoginAt | date: 'MMM d, y HH:mm') : 'never' }}</td>
            <td>
              <span class="cms-badge" [class.cms-badge-draft]="u.disabled">{{ u.disabled ? 'Disabled' : 'Active' }}</span>
              @if (isLocked(u)) { <span class="cms-badge cms-badge-draft">Locked</span> }
            </td>
            <td class="cms-row">
              @if (u.id !== me()) {
                <button type="button" class="cms-btn cms-btn-ghost" (click)="toggle(u)">{{ u.disabled ? 'Enable' : 'Disable' }}</button>
                <button type="button" class="cms-btn cms-btn-ghost" (click)="resetFor.set(u)">Reset password</button>
                <button type="button" class="cms-btn cms-btn-ghost cms-danger-text" (click)="remove(u)">Delete</button>
              }
            </td>
          </tr>
        }
      </tbody>
    </table>

    @if (resetFor(); as u) {
      <form class="cms-card cms-inline-form" (ngSubmit)="reset(u)">
        <h2>New password for {{ u.email }}</h2>
        <input type="password" name="pw" autocomplete="new-password" placeholder="At least 12 characters" [(ngModel)]="resetPw" />
        <div class="cms-row">
          <button class="cms-btn cms-btn-primary" type="submit">Set password</button>
          <button class="cms-btn cms-btn-ghost" type="button" (click)="resetFor.set(null)">Cancel</button>
        </div>
        <small class="cms-muted">This also clears any lockout and signs them out everywhere.</small>
      </form>
    }

    <form class="cms-card cms-inline-form" (ngSubmit)="create()">
      <h2>Add an administrator</h2>
      <div class="cms-row">
        <input type="email" name="email" placeholder="Email" autocomplete="off" required [(ngModel)]="nu.email" />
        <input type="text" name="name" placeholder="Name" [(ngModel)]="nu.name" />
        <input type="password" name="password" placeholder="Initial password (12+ chars)" autocomplete="new-password" [(ngModel)]="nu.password" />
        <button class="cms-btn cms-btn-primary" type="submit">Add</button>
      </div>
      <small class="cms-muted">Share the initial password securely; they can change it under their account.</small>
    </form>
  `,
})
export class Users {
  private readonly api = inject(AdminApi);
  private readonly notice = inject(NoticeService);
  protected readonly users = signal<AdminUser[]>([]);
  protected readonly error = signal('');
  protected readonly resetFor = signal<AdminUser | null>(null);
  protected resetPw = '';
  protected nu = { email: '', name: '', password: '' };
  private readonly auth = inject(AuthService);
  protected readonly me = computed(() => this.auth.user()?.id);

  constructor() {
    inject(Title).setTitle('Administrators – AZMA CMS');
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.users.set(await this.api.users());
    } catch (e) {
      this.error.set(errorMessage(e));
    }
  }

  protected isLocked(u: AdminUser): boolean {
    return !!u.lockedUntil && new Date(u.lockedUntil) > new Date();
  }

  protected async create(): Promise<void> {
    try {
      await this.api.createUser(this.nu);
      this.notice.ok(`Added ${this.nu.email}.`);
      this.nu = { email: '', name: '', password: '' };
      await this.load();
    } catch (e) {
      this.notice.error(errorMessage(e));
    }
  }

  protected async toggle(u: AdminUser): Promise<void> {
    try {
      await this.api.updateUser(u.id, { name: u.name, disabled: !u.disabled });
      this.notice.ok(`${u.email} ${u.disabled ? 'enabled' : 'disabled'}.`);
      await this.load();
    } catch (e) {
      this.notice.error(errorMessage(e));
    }
  }

  protected async reset(u: AdminUser): Promise<void> {
    try {
      await this.api.setUserPassword(u.id, this.resetPw);
      this.notice.ok(`Password reset for ${u.email}.`);
      this.resetPw = '';
      this.resetFor.set(null);
      await this.load();
    } catch (e) {
      this.notice.error(errorMessage(e));
    }
  }

  protected async remove(u: AdminUser): Promise<void> {
    if (!confirm(`Delete ${u.email}? Their edits stay in the activity log.`)) return;
    try {
      await this.api.deleteUser(u.id);
      this.notice.ok(`Deleted ${u.email}.`);
      await this.load();
    } catch (e) {
      this.notice.error(errorMessage(e));
    }
  }
}

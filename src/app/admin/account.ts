import { Component, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { AdminApi } from './admin-api.service';
import { AuthService } from './auth.service';
import { errorMessage } from './auth.interceptor';
import { NoticeService } from './shared/notice.service';

@Component({
  selector: 'cms-account',
  imports: [FormsModule],
  template: `
    <header class="cms-head"><h1>Your account</h1></header>
    <p>{{ auth.user()?.email }}</p>
    <form class="cms-card cms-inline-form" (ngSubmit)="change()">
      <h2>Change password</h2>
      <label class="cms-field"><span class="cms-label">Current password</span>
        <input type="password" name="cur" autocomplete="current-password" [(ngModel)]="cur" /></label>
      <label class="cms-field"><span class="cms-label">New password (at least 12 characters)</span>
        <input type="password" name="next" autocomplete="new-password" [(ngModel)]="next" /></label>
      <label class="cms-field"><span class="cms-label">Confirm new password</span>
        <input type="password" name="confirm" autocomplete="new-password" [(ngModel)]="confirm" /></label>
      <button class="cms-btn cms-btn-primary" type="submit">Change password</button>
      <small class="cms-muted">Other devices you are signed in on will be signed out.</small>
    </form>
  `,
})
export class Account {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(AdminApi);
  private readonly notice = inject(NoticeService);
  protected cur = '';
  protected next = '';
  protected confirm = '';

  constructor() {
    inject(Title).setTitle('Your account – AZMA CMS');
  }

  protected async change(): Promise<void> {
    if (this.next !== this.confirm) {
      this.notice.error('The new passwords do not match.');
      return;
    }
    try {
      await this.api.changeOwnPassword(this.cur, this.next);
      this.cur = this.next = this.confirm = '';
      this.notice.ok('Password changed.');
    } catch (e) {
      this.notice.error(errorMessage(e));
    }
  }
}

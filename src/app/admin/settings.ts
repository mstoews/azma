import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { SiteContentService } from '../content.service';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { AdminSettings } from './models';
import { ImageField } from './shared/image-field';
import { NoticeService } from './shared/notice.service';

@Component({
  selector: 'cms-settings',
  imports: [FormsModule, ImageField],
  template: `
    <header class="cms-head">
      <h1>Site settings</h1>
      <button type="button" class="cms-btn cms-btn-primary" (click)="save()" [disabled]="busy() || !dirty()">Save</button>
    </header>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    @if (s(); as v) {
      <div class="cms-edit-grid">
        <div class="cms-edit-main">
          <label class="cms-field"><span class="cms-label">Site name</span>
            <input type="text" [ngModel]="v.siteName" (ngModelChange)="patch({ siteName: $event })" /></label>
          <label class="cms-field"><span class="cms-label">Tagline (under the logo, and in the browser title)</span>
            <input type="text" [ngModel]="v.tagline" (ngModelChange)="patch({ tagline: $event })" /></label>
          <label class="cms-field"><span class="cms-label">Home page description</span>
            <textarea rows="2" [ngModel]="v.homeDescription" (ngModelChange)="patch({ homeDescription: $event })"></textarea></label>
        </div>
        <aside class="cms-edit-side">
          <div class="cms-card"><cms-image-field label="Logo" [value]="v.logo" (valueChange)="patch({ logo: $event })" /></div>
          <div class="cms-card"><cms-image-field label="Home page side image" [value]="v.homeHeaderImage" (valueChange)="patch({ homeHeaderImage: $event })" /></div>
        </aside>
      </div>
    }
  `,
})
export class Settings {
  private readonly api = inject(AdminApi);
  private readonly notice = inject(NoticeService);
  private readonly site = inject(SiteContentService);
  protected readonly s = signal<AdminSettings | null>(null);
  private readonly baseline = signal('');
  protected readonly dirty = computed(() => JSON.stringify(this.s()) !== this.baseline());
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    inject(Title).setTitle('Site settings – AZMA CMS');
    this.api.settings().then((v) => this.set(v), (e) => this.error.set(errorMessage(e)));
  }

  private set(v: AdminSettings): void {
    const { updatedAt: _, ...rest } = v;
    this.s.set(rest);
    this.baseline.set(JSON.stringify(rest));
  }

  protected patch(p: Partial<AdminSettings>): void {
    this.s.update((v) => (v ? { ...v, ...p } : v));
  }

  protected async save(): Promise<void> {
    const v = this.s();
    if (!v) return;
    this.busy.set(true);
    this.error.set('');
    try {
      this.set(await this.api.saveSettings(v));
      this.notice.ok('Settings saved.');
      this.site.refresh();
    } catch (e) {
      this.error.set(errorMessage(e));
    } finally {
      this.busy.set(false);
    }
  }
}

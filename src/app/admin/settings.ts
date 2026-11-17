import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { SiteContentService } from '../content.service';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { AdminSettings, CONTENT_LOCALES, ContentLocale, EditLocale, SettingsTranslation } from './models';
import { ImageField } from './shared/image-field';
import { LanguageTabs } from './shared/language-tabs';
import { NoticeService } from './shared/notice.service';

@Component({
  selector: 'cms-settings',
  imports: [FormsModule, ImageField, LanguageTabs],
  template: `
    <header class="cms-head">
      <h1>Site settings</h1>
      <button type="button" class="cms-btn cms-btn-primary" (click)="save()" [disabled]="busy() || !dirty()">Save</button>
    </header>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    @if (s(); as v) {
      <cms-language-tabs [(value)]="lang" [translated]="translatedLocales()" />
      <div class="cms-edit-grid">
        <div class="cms-edit-main">
          @if (lang() === 'en') {
          <label class="cms-field"><span class="cms-label">Site name</span>
            <input type="text" [ngModel]="v.siteName" (ngModelChange)="patch({ siteName: $event })" /></label>
          <label class="cms-field"><span class="cms-label">Tagline (under the home page headline, in the footer and the browser title)</span>
            <input type="text" [ngModel]="v.tagline" (ngModelChange)="patch({ tagline: $event })" /></label>
          <label class="cms-field"><span class="cms-label">Home page headline</span>
            <textarea rows="2" [ngModel]="v.homeDescription" (ngModelChange)="patch({ homeDescription: $event })"></textarea></label>
          } @else {
            @let t = currentTr();
            <p class="cms-muted cms-translate-note">Fields left blank show the English text. Images are shared with English.</p>
            <label class="cms-field"><span class="cms-label">Site name</span>
              <input type="text" [ngModel]="t.siteName" (ngModelChange)="patchTr({ siteName: $event })" [placeholder]="v.siteName" /></label>
            <label class="cms-field"><span class="cms-label">Tagline</span>
              <input type="text" [ngModel]="t.tagline" (ngModelChange)="patchTr({ tagline: $event })" [placeholder]="v.tagline" /></label>
            <label class="cms-field"><span class="cms-label">Home page headline</span>
              <textarea rows="2" [ngModel]="t.homeDescription" (ngModelChange)="patchTr({ homeDescription: $event })"
                        [placeholder]="v.homeDescription"></textarea></label>
          }
        </div>
        <aside class="cms-edit-side">
          <div class="cms-card"><cms-image-field label="Logo" hint="Not shown by the current site design." [value]="v.logo" (valueChange)="patch({ logo: $event })" /></div>
          <div class="cms-card"><cms-image-field label="Home page hero image" [value]="v.homeHeaderImage" (valueChange)="patch({ homeHeaderImage: $event })" /></div>
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
  protected readonly lang = signal<EditLocale>('en');
  protected readonly currentTr = computed((): SettingsTranslation => {
    const l = this.lang();
    return (l !== 'en' && this.s()?.translations?.[l]) || { siteName: '', tagline: '', homeDescription: '' };
  });
  protected readonly translatedLocales = computed(() =>
    CONTENT_LOCALES.map((l) => l.code).filter((c) => {
      const t = this.s()?.translations?.[c];
      return !!t && !!(t.siteName.trim() || t.tagline.trim() || t.homeDescription.trim());
    }),
  );
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
    // Every locale gets an entry, so the form can bind to it and saving a
    // cleared translation removes it on the server.
    const translations: Partial<Record<ContentLocale, SettingsTranslation>> = {};
    for (const { code } of CONTENT_LOCALES) {
      translations[code] = { siteName: '', tagline: '', homeDescription: '', ...rest.translations?.[code] };
    }
    const next = { ...rest, translations };
    this.s.set(next);
    this.baseline.set(JSON.stringify(next));
  }

  protected patchTr(p: Partial<SettingsTranslation>): void {
    const l = this.lang();
    if (l === 'en') return;
    this.s.update((v) => (v ? { ...v, translations: { ...v.translations, [l]: { ...this.currentTr(), ...p } } } : v));
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

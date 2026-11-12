import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom, timeout } from 'rxjs';
import { SiteContent, bundledContent } from './site-data';

/** Public site content, loaded once from the CMS at startup. */
@Injectable({ providedIn: 'root' })
export class SiteContentService {
  private readonly http = inject(HttpClient);
  private readonly content = signal<SiteContent>(bundledContent());

  /** 'api' once the CMS answered; 'bundled' when it could not be reached. */
  readonly source = signal<'api' | 'bundled'>('bundled');

  readonly settings = computed(() => this.content().settings);
  readonly pages = computed(() => this.content().pages);
  readonly profiles = computed(() => this.content().profiles);
  readonly nav = computed(() => this.content().nav);

  async load(): Promise<void> {
    try {
      const c = await firstValueFrom(this.http.get<SiteContent>('/api/v1/site').pipe(timeout(8000)));
      this.content.set(c);
      this.source.set('api');
    } catch (err) {
      console.warn('[cms] content API unavailable; showing bundled content', err);
    }
  }

  /** Re-fetch after an admin edit so the site reflects it without a reload. */
  refresh(): Promise<void> {
    return this.load();
  }
}

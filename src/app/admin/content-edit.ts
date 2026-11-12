import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { ActivatedRoute, CanDeactivateFn, Router, RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { slugify } from '../site-data';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { ContentKind } from './content-list';
import { AdminProfile, ProfileInput } from './models';
import { HtmlEditor } from './shared/html-editor';
import { ImageField } from './shared/image-field';
import { NoticeService } from './shared/notice.service';

interface Draft extends ProfileInput {
  excerptText: string;
}

const empty = (): Draft => ({
  slug: '', title: '', hero: '', content: '', published: false, sortOrder: 0, excerpt: [], thumb: '', excerptText: '',
});

/** Editor for one page or team profile (route data `kind`; `:id` or `new`). */
@Component({
  selector: 'cms-content-edit',
  imports: [FormsModule, RouterLink, HtmlEditor, ImageField],
  template: `
    <header class="cms-head">
      <div>
        <a [routerLink]="listUrl" class="cms-muted">← {{ kind === 'page' ? 'Pages' : 'Team profiles' }}</a>
        <h1>{{ id ? (draft().title || 'Untitled') : (kind === 'page' ? 'New page' : 'New profile') }}</h1>
      </div>
      <div class="cms-row">
        @if (id && saved()?.published) {
          <a [href]="publicUrl()" target="_blank" rel="noopener" class="cms-btn cms-btn-ghost">View on site ↗</a>
        }
        <button type="button" class="cms-btn cms-btn-primary" (click)="save()" [disabled]="busy() || !dirty()">
          {{ busy() ? 'Saving…' : 'Save' }}
        </button>
      </div>
    </header>

    @if (error()) { <p class="cms-error" role="alert">{{ error() }}</p> }

    @if (loaded()) {
      <div class="cms-edit-grid">
        <div class="cms-edit-main">
          <label class="cms-field">
            <span class="cms-label">{{ kind === 'page' ? 'Title' : 'Name' }}</span>
            <input type="text" [ngModel]="draft().title" (ngModelChange)="setTitle($event)" required />
          </label>
          <label class="cms-field">
            <span class="cms-label">URL</span>
            <div class="cms-prefixed"><span>{{ prefix }}</span>
              <input type="text" [ngModel]="draft().slug" (ngModelChange)="setSlug($event)" placeholder="auto from title" />
            </div>
            <small class="cms-muted">Lowercase letters, digits and hyphens. Changing it breaks existing links.</small>
          </label>
          @if (kind === 'profile') {
            <label class="cms-field">
              <span class="cms-label">Card text (one line each: Japanese name, role, office)</span>
              <textarea rows="3" [ngModel]="draft().excerptText" (ngModelChange)="patch({ excerptText: $event })"></textarea>
            </label>
          }
          <div class="cms-field">
            <span class="cms-label">Content</span>
            <cms-html-editor [value]="draft().content" (valueChange)="patch({ content: $event })" />
          </div>
        </div>
        <aside class="cms-edit-side">
          <div class="cms-card">
            <label class="cms-check">
              <input type="checkbox" [ngModel]="draft().published" (ngModelChange)="patch({ published: $event })" />
              Published
            </label>
            <small class="cms-muted">Drafts are hidden from the public site.</small>
          </div>
          <div class="cms-card">
            <cms-image-field label="Side image" hint="Shown in the left panel of the page."
                             [value]="draft().hero" (valueChange)="patch({ hero: $event })" />
          </div>
          @if (kind === 'profile') {
            <div class="cms-card">
              <cms-image-field label="Card image" hint="Shown on the home page list. Portrait, about 768×860."
                               [value]="draft().thumb" (valueChange)="patch({ thumb: $event })" />
            </div>
          }
          @if (id) {
            <div class="cms-card">
              @if (saved()?.legacyWpId) { <p class="cms-muted">WordPress ID {{ saved()?.legacyWpId }} — old links redirect here.</p> }
              <button type="button" class="cms-btn cms-btn-danger" (click)="remove()" [disabled]="busy()">
                Delete {{ kind === 'page' ? 'page' : 'profile' }}
              </button>
            </div>
          }
        </aside>
      </div>
    }
  `,
})
export class ContentEdit {
  private readonly api = inject(AdminApi);
  private readonly router = inject(Router);
  private readonly notice = inject(NoticeService);
  private readonly site = inject(SiteContentService);
  private readonly route = inject(ActivatedRoute);

  protected readonly kind: ContentKind = this.route.snapshot.data['kind'];
  protected readonly listUrl = this.kind === 'page' ? '/admin/pages' : '/admin/profiles';
  protected readonly prefix = this.kind === 'page' ? '/' : '/profile/';
  protected id = Number(this.route.snapshot.paramMap.get('id')) || 0;

  protected readonly draft = signal<Draft>(empty());
  protected readonly saved = signal<AdminProfile | null>(null);
  private readonly baseline = signal(JSON.stringify(empty()));
  private slugTouched = false;

  protected readonly loaded = signal(false);
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  readonly dirty = computed(() => JSON.stringify(this.draft()) !== this.baseline());
  protected readonly publicUrl = computed(() => this.prefix + (this.saved()?.slug ?? ''));

  private readonly title = inject(Title);

  constructor() {
    this.load();
  }

  private async load(): Promise<void> {
    const label = this.kind === 'page' ? 'page' : 'profile';
    if (!this.id) {
      this.title.setTitle(`New ${label} – AZMA CMS`);
      this.loaded.set(true);
      return;
    }
    try {
      const row = (this.kind === 'page' ? await this.api.page(this.id) : await this.api.profile(this.id)) as AdminProfile;
      this.apply(row);
      this.slugTouched = true;
      this.title.setTitle(`${row.title} – AZMA CMS`);
      this.loaded.set(true);
    } catch (e) {
      this.error.set(errorMessage(e));
    }
  }

  private apply(row: AdminProfile): void {
    const d: Draft = {
      slug: row.slug, title: row.title, hero: row.hero, content: row.content, published: row.published,
      sortOrder: row.sortOrder, excerpt: row.excerpt ?? [], thumb: row.thumb ?? '',
      excerptText: (row.excerpt ?? []).join('\n'),
    };
    this.saved.set(row);
    this.draft.set(d);
    this.baseline.set(JSON.stringify(d));
  }

  protected patch(p: Partial<Draft>): void {
    this.draft.update((d) => ({ ...d, ...p }));
  }

  protected setTitle(title: string): void {
    this.patch(this.slugTouched ? { title } : { title, slug: slugify(title) });
  }

  protected setSlug(slug: string): void {
    this.slugTouched = slug !== '';
    this.patch({ slug });
  }

  protected async save(): Promise<void> {
    const d = this.draft();
    const input: ProfileInput = {
      slug: d.slug, title: d.title, hero: d.hero, content: d.content, published: d.published, sortOrder: d.sortOrder,
      excerpt: d.excerptText.split('\n'), thumb: d.thumb,
    };
    this.busy.set(true);
    this.error.set('');
    try {
      let row: AdminProfile;
      if (this.kind === 'page') {
        row = (this.id ? await this.api.updatePage(this.id, input) : await this.api.createPage(input)) as AdminProfile;
      } else {
        row = this.id ? await this.api.updateProfile(this.id, input) : await this.api.createProfile(input);
      }
      this.apply(row);
      this.notice.ok(`Saved “${row.title}”.`);
      this.site.refresh();
      if (!this.id) {
        this.id = row.id;
        await this.router.navigate([this.listUrl, row.id], { replaceUrl: true });
      }
    } catch (e) {
      this.error.set(errorMessage(e));
    } finally {
      this.busy.set(false);
    }
  }

  protected async remove(): Promise<void> {
    const what = this.kind === 'page' ? 'page' : 'profile';
    if (!confirm(`Delete this ${what}? This cannot be undone from the admin.`)) return;
    this.busy.set(true);
    try {
      if (this.kind === 'page') await this.api.deletePage(this.id);
      else await this.api.deleteProfile(this.id);
      this.baseline.set(JSON.stringify(this.draft())); // nothing left to lose
      this.notice.ok(`Deleted the ${what}.`);
      this.site.refresh();
      await this.router.navigateByUrl(this.listUrl);
    } catch (e) {
      this.error.set(errorMessage(e));
      this.busy.set(false);
    }
  }
}

/** Warns before leaving the editor with unsaved changes. */
export const unsavedChangesGuard: CanDeactivateFn<ContentEdit> = (c) =>
  !c.dirty() || confirm('You have unsaved changes. Leave without saving?');

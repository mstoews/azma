import { DatePipe } from '@angular/common';
import { CdkDrag, CdkDragDrop, CdkDragHandle, CdkDropList, moveItemInArray } from '@angular/cdk/drag-drop';
import { Component, ElementRef, computed, effect, inject, signal, viewChild } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { AdminPage, AdminProfile, CONTENT_LOCALES, ProfileTranslation } from './models';
import { Icon } from './shared/icon';
import { keepRowWidths } from './shared/table-drag';
import { NoticeService } from './shared/notice.service';

export type ContentKind = 'page' | 'profile';
type StatusFilter = 'all' | 'published' | 'draft';

const STATUSES: StatusFilter[] = ['all', 'published', 'draft'];

/** Case-, width- and accent-insensitive form for matching (so "ｓａｔｏ" finds "Sato"). */
const fold = (s: string) => s.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();

/** List of pages or team profiles (route data `kind`), with ordering. */
@Component({
  selector: 'cms-content-list',
  imports: [RouterLink, DatePipe, CdkDropList, CdkDrag, CdkDragHandle, Icon],
  host: { '(document:keydown)': 'focusSearch($event)' },
  template: `
    <header class="cms-head">
      <h1>{{ kind === 'page' ? 'Pages' : 'Team profiles' }}</h1>
      <a [routerLink]="['new']" class="cms-btn cms-btn-primary">{{ kind === 'page' ? 'New page' : 'New profile' }}</a>
    </header>
    <p class="cms-muted">
      @if (kind === 'page') { Each page lives at its own URL; add it to the Menu to link it. }
      @else { Profiles are listed on the home page in this order. }
      Drag rows by the handle (or use the arrows) to reorder, then save the order.
    </p>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <div class="cms-toolbar" role="search">
      <label class="cms-search">
        <cms-icon name="search" />
        <span class="cms-visually-hidden">Search {{ kind === 'page' ? 'pages' : 'profiles' }}</span>
        <input #search type="search" [value]="query()" (input)="query.set(search.value)" (keydown.escape)="query.set('')"
               [placeholder]="kind === 'page' ? 'Search title, URL or translation…' : 'Search name, role, office…'" />
        <kbd aria-hidden="true">/</kbd>
      </label>
      <div class="cms-seg" role="group" aria-label="Status">
        @for (s of statuses; track s) {
          <button type="button" [class.active]="status() === s" [attr.aria-pressed]="status() === s" (click)="status.set(s)">
            {{ s === 'all' ? 'All' : s === 'published' ? 'Published' : 'Drafts' }}<span class="cms-count">{{ counts()[s] }}</span>
          </button>
        }
      </div>
      @if (filtering()) {
        <span class="cms-muted cms-toolbar-note" aria-live="polite">
          {{ visible().length }} of {{ items().length }} · reordering is off while filtered
          <button type="button" class="cms-linkbtn" (click)="clearFilters()">Clear</button>
        </span>
      }
    </div>
    <table class="cms-table" [class.cms-filtered]="filtering()">
      <thead><tr><th></th><th>Title</th><th>URL</th><th>Status</th><th>Updated</th></tr></thead>
      <tbody cdkDropList cdkDropListLockAxis="y" [cdkDropListDisabled]="filtering()" (cdkDropListDropped)="drop($event)">
        @for (item of visible(); track item.id; let i = $index, first = $first, last = $last) {
          <tr cdkDrag cdkDragPreviewContainer="parent" (cdkDragStarted)="keepRowWidths($event)">
            <td class="cms-order" [attr.inert]="filtering() ? '' : null">
              <span class="cms-drag-handle" cdkDragHandle title="Drag to reorder"><cms-icon name="grip" /></span>
              <button type="button" (click)="move(i, -1)" [disabled]="first" aria-label="Move up">↑</button>
              <button type="button" (click)="move(i, 1)" [disabled]="last" aria-label="Move down">↓</button>
            </td>
            <td>
              <a [routerLink]="[item.id]"><strong>{{ item.title }}</strong></a>
              @if (excerptOf(item); as ex) { <div class="cms-muted">{{ ex }}</div> }
            </td>
            <td class="cms-muted">{{ prefix }}{{ item.slug }}</td>
            <td>
              <span class="cms-badge" [class.cms-badge-draft]="!item.published">{{ item.published ? 'Published' : 'Draft' }}</span>
              @for (l of locales; track l.code) {
                @if (item.translations?.[l.code]) { <span class="cms-badge" [title]="'Translated into ' + l.label">{{ l.label }}</span> }
              }
            </td>
            <td class="cms-muted">{{ item.updatedAt | date: 'MMM d, y' }}</td>
          </tr>
        } @empty {
          <tr><td colspan="5" class="cms-muted cms-empty-row">
            @if (loading()) { Loading… }
            @else if (filtering() && items().length) {
              Nothing matches{{ query().trim() ? ' “' + query().trim() + '”' : '' }}.
              <button type="button" class="cms-linkbtn" (click)="clearFilters()">Clear filters</button>
            } @else { Nothing here yet. }
          </td></tr>
        }
      </tbody>
    </table>
    @if (orderChanged()) {
      <div class="cms-row cms-sticky">
        <button type="button" class="cms-btn cms-btn-primary" (click)="saveOrder()" [disabled]="busy()">Save order</button>
        <button type="button" class="cms-btn cms-btn-ghost" (click)="load()">Discard</button>
      </div>
    }
  `,
})
export class ContentList {
  private readonly api = inject(AdminApi);
  private readonly notice = inject(NoticeService);
  private readonly site = inject(SiteContentService);
  protected readonly kind: ContentKind = inject(ActivatedRoute).snapshot.data['kind'];
  protected readonly prefix = this.kind === 'page' ? '/' : '/profile/';
  protected readonly locales = CONTENT_LOCALES;

  protected readonly items = signal<(AdminPage | AdminProfile)[]>([]);
  private readonly original = signal<number[]>([]);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly searchBox = viewChild.required<ElementRef<HTMLInputElement>>('search');
  protected readonly statuses = STATUSES;

  /** Filters live in the URL (?q=&status=) so they survive opening an item and coming back. */
  protected readonly query = signal(this.route.snapshot.queryParamMap.get('q') ?? '');
  protected readonly status = signal<StatusFilter>(
    STATUSES.find((s) => s === this.route.snapshot.queryParamMap.get('status')) ?? 'all',
  );
  protected readonly filtering = computed(() => !!this.query().trim() || this.status() !== 'all');

  protected readonly counts = computed(() => {
    const xs = this.items();
    const published = xs.filter((x) => x.published).length;
    return { all: xs.length, published, draft: xs.length - published };
  });

  protected readonly visible = computed(() => {
    const terms = fold(this.query()).split(/\s+/).filter(Boolean);
    const status = this.status();
    return this.items().filter((item) => {
      if (status !== 'all' && item.published !== (status === 'published')) return false;
      if (!terms.length) return true;
      const hay = fold(this.searchText(item));
      return terms.every((t) => hay.includes(t));
    });
  });

  protected readonly orderChanged = computed(() => this.items().map((x) => x.id).join() !== this.original().join());

  constructor() {
    inject(Title).setTitle(`${this.kind === 'page' ? 'Pages' : 'Team profiles'} – AZMA CMS`);
    this.load();
    effect(() => {
      const q = this.query().trim() || null;
      const status = this.status() === 'all' ? null : this.status();
      this.router.navigate([], { queryParams: { q, status }, queryParamsHandling: 'merge', replaceUrl: true });
    });
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    try {
      const rows = this.kind === 'page' ? await this.api.pages() : await this.api.profiles();
      this.items.set(rows);
      this.original.set(rows.map((r) => r.id));
    } catch (e) {
      this.error.set(errorMessage(e));
    } finally {
      this.loading.set(false);
    }
  }

  /** Everything a search can match: title, URL, card text and translations. */
  private searchText(item: AdminPage | AdminProfile): string {
    const parts = [item.title, this.prefix + item.slug];
    if ('excerpt' in item) parts.push(...item.excerpt);
    for (const tr of Object.values(item.translations ?? {}) as (Partial<ProfileTranslation> | undefined)[]) {
      if (tr?.title) parts.push(tr.title);
      if (tr?.excerpt) parts.push(...tr.excerpt);
    }
    return parts.join('\n');
  }

  protected clearFilters(): void {
    this.query.set('');
    this.status.set('all');
    this.searchBox().nativeElement.focus();
  }

  /** "/" jumps to the search box, as on GitHub and most docs sites. */
  protected focusSearch(e: KeyboardEvent): void {
    if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return;
    const t = e.target as HTMLElement | null;
    if (t?.closest('input, textarea, select, [contenteditable]')) return;
    e.preventDefault();
    this.searchBox().nativeElement.focus();
  }

  protected excerptOf(item: AdminPage | AdminProfile): string {
    return 'excerpt' in item ? item.excerpt.slice(1).join(' · ') : '';
  }

  protected readonly keepRowWidths = keepRowWidths;

  protected drop(e: CdkDragDrop<unknown>): void {
    if (e.previousIndex === e.currentIndex) return;
    this.items.update((xs) => {
      const next = [...xs];
      moveItemInArray(next, e.previousIndex, e.currentIndex);
      return next;
    });
  }

  protected move(i: number, d: number): void {
    this.items.update((xs) => {
      const next = [...xs];
      [next[i], next[i + d]] = [next[i + d], next[i]];
      return next;
    });
  }

  protected async saveOrder(): Promise<void> {
    this.busy.set(true);
    const ids = this.items().map((x) => x.id);
    try {
      if (this.kind === 'page') await this.api.reorderPages(ids);
      else await this.api.reorderProfiles(ids);
      this.original.set(ids);
      this.notice.ok('Order saved.');
      this.site.refresh();
    } catch (e) {
      this.notice.error(errorMessage(e));
    } finally {
      this.busy.set(false);
    }
  }
}

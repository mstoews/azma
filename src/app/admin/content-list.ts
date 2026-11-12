import { DatePipe } from '@angular/common';
import { Component, computed, inject, signal } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { AdminPage, AdminProfile } from './models';
import { NoticeService } from './shared/notice.service';

export type ContentKind = 'page' | 'profile';

/** List of pages or team profiles (route data `kind`), with ordering. */
@Component({
  selector: 'cms-content-list',
  imports: [RouterLink, DatePipe],
  template: `
    <header class="cms-head">
      <h1>{{ kind === 'page' ? 'Pages' : 'Team profiles' }}</h1>
      <a [routerLink]="['new']" class="cms-btn cms-btn-primary">{{ kind === 'page' ? 'New page' : 'New profile' }}</a>
    </header>
    <p class="cms-muted">
      @if (kind === 'page') { Each page lives at its own URL; add it to the Menu to link it. }
      @else { Profiles are listed on the home page in this order. }
      Use the arrows to reorder, then save the order.
    </p>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <table class="cms-table">
      <thead><tr><th></th><th>Title</th><th>URL</th><th>Status</th><th>Updated</th></tr></thead>
      <tbody>
        @for (item of items(); track item.id; let i = $index, first = $first, last = $last) {
          <tr>
            <td class="cms-order">
              <button type="button" (click)="move(i, -1)" [disabled]="first" aria-label="Move up">↑</button>
              <button type="button" (click)="move(i, 1)" [disabled]="last" aria-label="Move down">↓</button>
            </td>
            <td>
              <a [routerLink]="[item.id]"><strong>{{ item.title }}</strong></a>
              @if (excerptOf(item); as ex) { <div class="cms-muted">{{ ex }}</div> }
            </td>
            <td class="cms-muted">{{ prefix }}{{ item.slug }}</td>
            <td><span class="cms-badge" [class.cms-badge-draft]="!item.published">{{ item.published ? 'Published' : 'Draft' }}</span></td>
            <td class="cms-muted">{{ item.updatedAt | date: 'MMM d, y' }}</td>
          </tr>
        } @empty {
          <tr><td colspan="5" class="cms-muted">{{ loading() ? 'Loading…' : 'Nothing here yet.' }}</td></tr>
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

  protected readonly items = signal<(AdminPage | AdminProfile)[]>([]);
  private readonly original = signal<number[]>([]);
  protected readonly loading = signal(true);
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  protected readonly orderChanged = computed(() => this.items().map((x) => x.id).join() !== this.original().join());

  constructor() {
    inject(Title).setTitle(`${this.kind === 'page' ? 'Pages' : 'Team profiles'} – AZMA CMS`);
    this.load();
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

  protected excerptOf(item: AdminPage | AdminProfile): string {
    return 'excerpt' in item ? item.excerpt.slice(1).join(' · ') : '';
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

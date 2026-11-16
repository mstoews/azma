import { CdkDrag, CdkDragDrop, CdkDragHandle, CdkDropList, moveItemInArray } from '@angular/cdk/drag-drop';
import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { SiteContentService } from '../content.service';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { AdminNavItem, AdminPage, CONTENT_LOCALES, ContentLocale } from './models';
import { Icon } from './shared/icon';
import { keepRowWidths } from './shared/table-drag';
import { NoticeService } from './shared/notice.service';

interface Row {
  label: string;
  type: 'page' | 'url';
  pageId: number | null;
  href: string;
  labels: Partial<Record<ContentLocale, string>>;
}

const toRow = (n: AdminNavItem): Row => ({
  label: n.label, type: n.pageId ? 'page' : 'url', pageId: n.pageId, href: n.href, labels: { ...n.labels },
});

@Component({
  selector: 'cms-nav-editor',
  imports: [FormsModule, CdkDropList, CdkDrag, CdkDragHandle, Icon],
  template: `
    <header class="cms-head">
      <h1>Menu</h1>
      <button type="button" class="cms-btn cms-btn-primary" (click)="save()" [disabled]="busy() || !dirty()">Save menu</button>
    </header>
    <p class="cms-muted">
      The site's slide-out menu. Links to draft pages are hidden until the page is published.
      A blank translated label shows the linked page's translated title, or the English label.
    </p>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <table class="cms-table cms-nav-table">
      <thead><tr><th></th><th>Label</th>@for (l of locales; track l.code) { <th>{{ l.label }}</th> }<th>Links to</th><th></th></tr></thead>
      <tbody cdkDropList cdkDropListLockAxis="y" (cdkDropListDropped)="drop($event)">
        @for (r of rows(); track $index; let i = $index, first = $first, last = $last) {
          <tr cdkDrag cdkDragPreviewContainer="parent" (cdkDragStarted)="keepRowWidths($event)">
            <td class="cms-order">
              <span class="cms-drag-handle" cdkDragHandle title="Drag to reorder"><cms-icon name="grip" /></span>
              <button type="button" (click)="move(i, -1)" [disabled]="first" aria-label="Move up">↑</button>
              <button type="button" (click)="move(i, 1)" [disabled]="last" aria-label="Move down">↓</button>
            </td>
            <td><input type="text" [ngModel]="r.label" (ngModelChange)="update(i, { label: $event })" /></td>
            @for (l of locales; track l.code) {
              <td><input type="text" [attr.lang]="l.code" [placeholder]="r.label" [ngModel]="r.labels[l.code] ?? ''"
                         (ngModelChange)="setLabel(i, l.code, $event)" /></td>
            }
            <td>
              <div class="cms-row">
                <select [ngModel]="r.type" (ngModelChange)="update(i, { type: $event })">
                  <option value="page">Page</option>
                  <option value="url">External URL</option>
                </select>
                @if (r.type === 'page') {
                  <select [ngModel]="r.pageId" (ngModelChange)="update(i, { pageId: +$event })">
                    <option [ngValue]="null" disabled>Choose a page…</option>
                    @for (p of pages(); track p.id) {
                      <option [ngValue]="p.id">{{ p.title }}{{ p.published ? '' : ' (draft)' }}</option>
                    }
                  </select>
                } @else {
                  <input type="url" placeholder="https://…" [ngModel]="r.href" (ngModelChange)="update(i, { href: $event })" />
                }
              </div>
            </td>
            <td><button type="button" class="cms-btn cms-btn-ghost" (click)="removeRow(i)">Remove</button></td>
          </tr>
        }
      </tbody>
    </table>
    <button type="button" class="cms-btn" (click)="add()">Add menu item</button>
  `,
})
export class NavEditor {
  private readonly api = inject(AdminApi);
  private readonly notice = inject(NoticeService);
  private readonly site = inject(SiteContentService);

  protected readonly locales = CONTENT_LOCALES;
  protected readonly rows = signal<Row[]>([]);
  protected readonly pages = signal<AdminPage[]>([]);
  private readonly baseline = signal('[]');
  protected readonly dirty = computed(() => JSON.stringify(this.rows()) !== this.baseline());
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  constructor() {
    inject(Title).setTitle('Menu – AZMA CMS');
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const [nav, pages] = await Promise.all([this.api.nav(), this.api.pages()]);
      this.pages.set(pages);
      this.setRows(nav.map(toRow));
    } catch (e) {
      this.error.set(errorMessage(e));
    }
  }

  private setRows(rows: Row[]): void {
    this.rows.set(rows);
    this.baseline.set(JSON.stringify(rows));
  }

  protected update(i: number, p: Partial<Row>): void {
    this.rows.update((rs) => rs.map((r, j) => (j === i ? { ...r, ...p } : r)));
  }

  protected setLabel(i: number, locale: ContentLocale, label: string): void {
    this.rows.update((rs) => rs.map((r, j) => (j === i ? { ...r, labels: { ...r.labels, [locale]: label } } : r)));
  }

  protected readonly keepRowWidths = keepRowWidths;

  protected drop(e: CdkDragDrop<unknown>): void {
    if (e.previousIndex === e.currentIndex) return;
    this.rows.update((xs) => {
      const next = [...xs];
      moveItemInArray(next, e.previousIndex, e.currentIndex);
      return next;
    });
  }

  protected move(i: number, d: number): void {
    this.rows.update((rs) => {
      const next = [...rs];
      [next[i], next[i + d]] = [next[i + d], next[i]];
      return next;
    });
  }

  protected add(): void {
    this.rows.update((rs) => [...rs, { label: '', type: 'page', pageId: null, href: '', labels: {} }]);
  }

  protected removeRow(i: number): void {
    this.rows.update((rs) => rs.filter((_, j) => j !== i));
  }

  protected async save(): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      const saved = await this.api.saveNav(
        this.rows().map((r) => ({
          label: r.label, pageId: r.type === 'page' ? r.pageId : null, href: r.type === 'url' ? r.href : '', labels: r.labels,
        })),
      );
      this.setRows(saved.map(toRow));
      this.notice.ok('Menu saved.');
      this.site.refresh();
    } catch (e) {
      this.error.set(errorMessage(e));
    } finally {
      this.busy.set(false);
    }
  }
}

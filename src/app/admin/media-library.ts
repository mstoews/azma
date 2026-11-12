import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Title } from '@angular/platform-browser';
import { AdminApi } from './admin-api.service';
import { errorMessage } from './auth.interceptor';
import { MediaItem } from './models';
import { NoticeService } from './shared/notice.service';

@Component({
  selector: 'cms-media-library',
  imports: [FormsModule, DatePipe],
  template: `
    <header class="cms-head">
      <h1>Media</h1>
      <label class="cms-btn cms-btn-primary">
        {{ uploading() ? 'Uploading ' + uploading() + '…' : 'Upload files' }}
        <input type="file" multiple accept="image/jpeg,image/png,image/gif,image/webp,application/pdf" hidden (change)="upload($event)" />
      </label>
    </header>
    <p class="cms-muted">JPEG, PNG, GIF, WebP or PDF. Drop files anywhere on this page to upload.</p>
    <div class="cms-row">
      <input type="search" placeholder="Filter by name" [ngModel]="filter()" (ngModelChange)="filter.set($event)" />
      <label class="cms-check"><input type="checkbox" [ngModel]="showWp()" (ngModelChange)="showWp.set($event)" /> Include original WordPress files</label>
    </div>
    @if (error()) { <p class="cms-error">{{ error() }}</p> }
    <div class="cms-media-layout" (dragover)="$event.preventDefault()" (drop)="drop($event)">
      <div class="cms-media-grid">
        @for (m of visible(); track m.id) {
          <button type="button" class="cms-media-tile" [class.selected]="selected()?.id === m.id" (click)="select(m)">
            @if (m.mimeType.startsWith('image/')) { <img [src]="m.url" [alt]="m.alt" loading="lazy" /> }
            @else { <span class="cms-file-icon">PDF</span> }
            <span>{{ m.filename }}</span>
          </button>
        } @empty { <p class="cms-muted">No files.</p> }
      </div>
      @if (selected(); as m) {
        <aside class="cms-card cms-media-detail">
          @if (m.mimeType.startsWith('image/')) { <img [src]="m.url" [alt]="m.alt" /> }
          <dl>
            <dt>File</dt><dd>{{ m.filename }}</dd>
            <dt>URL</dt><dd><code>{{ m.url }}</code></dd>
            @if (m.width) { <dt>Size</dt><dd>{{ m.width }} × {{ m.height }} px</dd> }
            @if (m.sizeBytes) { <dt>Bytes</dt><dd>{{ (m.sizeBytes / 1024).toFixed(0) }} KB</dd> }
            <dt>Added</dt><dd>{{ m.createdAt | date: 'MMM d, y' }} {{ m.source === 'wordpress' ? '(WordPress import)' : '' }}</dd>
          </dl>
          <label class="cms-field">
            <span class="cms-label">Alt text</span>
            <input type="text" [(ngModel)]="altDraft" (keyup.enter)="saveAlt(m)" />
          </label>
          <div class="cms-row">
            <button type="button" class="cms-btn" (click)="saveAlt(m)" [disabled]="altDraft === m.alt">Save alt text</button>
            <button type="button" class="cms-btn cms-btn-ghost" (click)="copy(m.url)">Copy URL</button>
          </div>
          <button type="button" class="cms-btn cms-btn-danger" (click)="remove(m)">Delete file</button>
        </aside>
      }
    </div>
  `,
})
export class MediaLibrary {
  private readonly api = inject(AdminApi);
  private readonly notice = inject(NoticeService);

  protected readonly items = signal<MediaItem[]>([]);
  protected readonly filter = signal('');
  protected readonly showWp = signal(true);
  protected readonly selected = signal<MediaItem | null>(null);
  protected readonly uploading = signal(0);
  protected readonly error = signal('');
  protected altDraft = '';

  protected readonly visible = computed(() => {
    const f = this.filter().toLowerCase();
    return this.items().filter((m) => (this.showWp() || m.source !== 'wordpress') && (!f || m.filename.toLowerCase().includes(f)));
  });

  constructor() {
    inject(Title).setTitle('Media – AZMA CMS');
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.items.set(await this.api.media());
    } catch (e) {
      this.error.set(errorMessage(e));
    }
  }

  protected select(m: MediaItem): void {
    this.selected.set(m);
    this.altDraft = m.alt;
  }

  protected upload(e: Event): void {
    const input = e.target as HTMLInputElement;
    const files = Array.from(input.files ?? []);
    input.value = '';
    this.uploadFiles(files);
  }

  protected drop(e: DragEvent): void {
    e.preventDefault();
    this.uploadFiles(Array.from(e.dataTransfer?.files ?? []));
  }

  private async uploadFiles(files: File[]): Promise<void> {
    for (const f of files) {
      this.uploading.update((n) => n + 1);
      try {
        const m = await this.api.uploadMedia(f);
        this.items.update((xs) => [m, ...xs]);
        this.select(m);
        this.notice.ok(`Uploaded ${f.name}.`);
      } catch (err) {
        this.notice.error(`${f.name}: ${errorMessage(err)}`);
      } finally {
        this.uploading.update((n) => n - 1);
      }
    }
  }

  protected async saveAlt(m: MediaItem): Promise<void> {
    try {
      const updated = await this.api.updateMediaAlt(m.id, this.altDraft);
      this.items.update((xs) => xs.map((x) => (x.id === m.id ? updated : x)));
      this.selected.set(updated);
      this.notice.ok('Alt text saved.');
    } catch (e) {
      this.notice.error(errorMessage(e));
    }
  }

  protected async copy(url: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(url);
      this.notice.ok('URL copied.');
    } catch {
      this.notice.error('Copy failed; select the URL and copy it manually.');
    }
  }

  protected async remove(m: MediaItem): Promise<void> {
    const note = m.source === 'wordpress' ? ' (The original WordPress file stays in the site build; only the library entry is removed.)' : '';
    if (!confirm(`Delete ${m.filename}?${note}`)) return;
    try {
      await this.api.deleteMedia(m.id);
    } catch (e) {
      if (!(e instanceof HttpErrorResponse && e.status === 409)) {
        this.notice.error(errorMessage(e));
        return;
      }
      if (!confirm(`${errorMessage(e)}. Deleting it will leave broken images. Delete anyway?`)) return;
      try {
        await this.api.deleteMedia(m.id, true);
      } catch (e2) {
        this.notice.error(errorMessage(e2));
        return;
      }
    }
    this.items.update((xs) => xs.filter((x) => x.id !== m.id));
    this.selected.set(null);
    this.notice.ok(`Deleted ${m.filename}.`);
  }
}

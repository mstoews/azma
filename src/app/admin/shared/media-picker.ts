import { Component, ElementRef, computed, inject, output, signal, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AdminApi } from '../admin-api.service';
import { errorMessage } from '../auth.interceptor';
import { MediaItem } from '../models';

/** Modal media library: pick an existing image or upload a new one. */
@Component({
  selector: 'cms-media-picker',
  imports: [FormsModule],
  template: `
    <dialog #dlg class="cms-dialog" (close)="closed.emit()" (click)="backdrop($event)">
      <div class="cms-dialog-head">
        <h2>Choose an image</h2>
        <input type="search" placeholder="Filter by name" [ngModel]="filter()" (ngModelChange)="filter.set($event)" />
        <label class="cms-btn">
          {{ uploading() ? 'Uploading…' : 'Upload new' }}
          <input type="file" accept="image/jpeg,image/png,image/gif,image/webp" hidden (change)="upload($event)" [disabled]="uploading()" />
        </label>
        <button type="button" class="cms-btn cms-btn-ghost" (click)="close()">Cancel</button>
      </div>
      @if (error()) { <p class="cms-error">{{ error() }}</p> }
      <div class="cms-media-grid">
        @for (m of visible(); track m.id) {
          <button type="button" class="cms-media-tile" (click)="pick(m)" [title]="m.filename">
            <img [src]="m.url" [alt]="m.alt" loading="lazy" />
            <span>{{ m.filename }}</span>
          </button>
        } @empty {
          <p class="cms-muted">{{ loading() ? 'Loading…' : 'No images yet.' }}</p>
        }
      </div>
    </dialog>
  `,
})
export class MediaPicker {
  private readonly api = inject(AdminApi);
  private readonly dlg = viewChild.required<ElementRef<HTMLDialogElement>>('dlg');

  readonly picked = output<MediaItem>();
  readonly closed = output<void>();

  protected readonly items = signal<MediaItem[]>([]);
  protected readonly loading = signal(false);
  protected readonly uploading = signal(false);
  protected readonly error = signal('');
  protected readonly filter = signal('');
  protected readonly visible = computed(() => {
    const f = this.filter().toLowerCase();
    return this.items().filter((m) => m.mimeType.startsWith('image/') && (!f || m.filename.toLowerCase().includes(f)));
  });

  async open(): Promise<void> {
    this.dlg().nativeElement.showModal();
    this.loading.set(true);
    this.error.set('');
    try {
      this.items.set(await this.api.media());
    } catch (e) {
      this.error.set(errorMessage(e));
    } finally {
      this.loading.set(false);
    }
  }

  close(): void { this.dlg().nativeElement.close(); }

  protected pick(m: MediaItem): void {
    this.picked.emit(m);
    this.close();
  }

  protected backdrop(e: MouseEvent): void {
    if (e.target === this.dlg().nativeElement) this.close();
  }

  protected async upload(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    this.uploading.set(true);
    this.error.set('');
    try {
      const m = await this.api.uploadMedia(file);
      this.items.update((xs) => [m, ...xs]);
      this.pick(m);
    } catch (err) {
      this.error.set(errorMessage(err));
    } finally {
      this.uploading.set(false);
    }
  }
}

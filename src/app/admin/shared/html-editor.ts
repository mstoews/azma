import { Component, ElementRef, effect, model, signal, untracked, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { MediaItem } from '../models';
import { MediaPicker } from './media-picker';

type Mode = 'visual' | 'html';

/**
 * Content editor with two views of the same HTML: a visual (contenteditable)
 * mode for everyday edits and a source mode for markup the toolbar does not
 * cover. Content comes from administrators and is rendered as trusted HTML on
 * the site, so no sanitizing happens here.
 */
@Component({
  selector: 'cms-html-editor',
  imports: [FormsModule, MediaPicker],
  template: `
    <div class="cms-editor">
      <div class="cms-editor-bar" role="toolbar" aria-label="Formatting">
        <div class="cms-tabs">
          <button type="button" [class.active]="mode() === 'visual'" (click)="setMode('visual')">Visual</button>
          <button type="button" [class.active]="mode() === 'html'" (click)="setMode('html')">HTML</button>
        </div>
        @if (mode() === 'visual') {
          <button type="button" title="Heading" (mousedown)="$event.preventDefault()" (click)="block('h2')">H2</button>
          <button type="button" title="Sub-heading" (mousedown)="$event.preventDefault()" (click)="block('h3')">H3</button>
          <button type="button" title="Paragraph" (mousedown)="$event.preventDefault()" (click)="block('p')">¶</button>
          <span class="cms-sep"></span>
          <button type="button" title="Bold" (mousedown)="$event.preventDefault()" (click)="cmd('bold')"><b>B</b></button>
          <button type="button" title="Italic" (mousedown)="$event.preventDefault()" (click)="cmd('italic')"><i>I</i></button>
          <button type="button" title="Bulleted list" (mousedown)="$event.preventDefault()" (click)="cmd('insertUnorderedList')">• List</button>
          <button type="button" title="Numbered list" (mousedown)="$event.preventDefault()" (click)="cmd('insertOrderedList')">1. List</button>
          <span class="cms-sep"></span>
          <button type="button" title="Link" (mousedown)="$event.preventDefault()" (click)="link()">Link</button>
          <button type="button" title="Remove link" (mousedown)="$event.preventDefault()" (click)="cmd('unlink')">Unlink</button>
          <button type="button" title="Insert image" (mousedown)="saveSelection()" (click)="picker.open()">Image</button>
          <button type="button" title="Clear formatting" (mousedown)="$event.preventDefault()" (click)="cmd('removeFormat')">Clear</button>
        }
      </div>
      @if (mode() === 'visual') {
        <div #visual class="cms-editor-visual entry-content" contenteditable="true" (input)="fromVisual()" (blur)="fromVisual()"></div>
      } @else {
        <textarea class="cms-editor-source" spellcheck="false" [ngModel]="value()" (ngModelChange)="value.set($event)"></textarea>
      }
      <cms-media-picker #picker (picked)="insertImage($event)" />
    </div>
  `,
})
export class HtmlEditor {
  readonly value = model('');
  protected readonly mode = signal<Mode>('visual');
  private readonly visual = viewChild<ElementRef<HTMLDivElement>>('visual');
  private savedRange: Range | null = null;
  /** Last HTML written by the visual editor, to avoid resetting the caret on our own updates. */
  private lastEmitted: string | null = null;

  constructor() {
    // Push external value changes (load, mode switch) into the visual editor.
    effect(() => {
      const el = this.visual()?.nativeElement;
      const v = this.value();
      if (!el) return;
      untracked(() => {
        if (v !== this.lastEmitted && el.innerHTML !== v) el.innerHTML = v;
      });
    });
  }

  protected setMode(m: Mode): void {
    if (m === this.mode()) return;
    if (this.mode() === 'visual') this.fromVisual();
    this.lastEmitted = null;
    this.mode.set(m);
  }

  protected fromVisual(): void {
    const el = this.visual()?.nativeElement;
    if (!el) return;
    const html = el.innerHTML;
    if (html !== this.value()) {
      this.lastEmitted = html;
      this.value.set(html);
    }
  }

  protected cmd(name: string, arg?: string): void {
    // execCommand is deprecated but remains the only built-in rich-text API
    // and works in every current browser.
    document.execCommand(name, false, arg);
    this.fromVisual();
  }

  protected block(tag: string): void { this.cmd('formatBlock', tag); }

  protected link(): void {
    const url = prompt('Link URL (https://…, /page, or mailto:…)');
    if (!url) return;
    if (!/^(https?:\/\/|\/|mailto:|tel:)/i.test(url.trim())) {
      alert('Links must start with https://, http://, /, mailto: or tel:');
      return;
    }
    this.cmd('createLink', url.trim());
  }

  protected saveSelection(): void {
    const sel = window.getSelection();
    const el = this.visual()?.nativeElement;
    this.savedRange = sel && sel.rangeCount && el?.contains(sel.anchorNode) ? sel.getRangeAt(0).cloneRange() : null;
  }

  protected insertImage(m: MediaItem): void {
    const el = this.visual()?.nativeElement;
    if (!el) return;
    el.focus();
    const sel = window.getSelection();
    if (this.savedRange && sel) {
      sel.removeAllRanges();
      sel.addRange(this.savedRange);
    } else if (sel) {
      sel.selectAllChildren(el);
      sel.collapseToEnd();
    }
    const alt = (m.alt || '').replace(/"/g, '&quot;');
    const size = m.width && m.height ? ` width="${m.width}" height="${m.height}"` : '';
    this.cmd('insertHTML', `<figure class="wp-block-image size-large"><img src="${m.url}" alt="${alt}"${size} /></figure><p></p>`);
  }
}

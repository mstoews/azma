import { Component, input, model } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { MediaPicker } from './media-picker';

/** URL field with a preview and a media-library picker. */
@Component({
  selector: 'cms-image-field',
  imports: [FormsModule, MediaPicker],
  template: `
    <div class="cms-field">
      <span class="cms-label">{{ label() }}</span>
      <div class="cms-image-field">
        <div class="cms-image-preview">
          @if (value()) { <img [src]="value()" alt="" /> } @else { <span>No image</span> }
        </div>
        <div class="cms-image-controls">
          <input type="text" [ngModel]="value()" (ngModelChange)="value.set($event)" placeholder="/media/… or https://…" />
          <div class="cms-row">
            <button type="button" class="cms-btn" (click)="picker.open()">Choose…</button>
            @if (value()) { <button type="button" class="cms-btn cms-btn-ghost" (click)="value.set('')">Remove</button> }
          </div>
          @if (hint()) { <small class="cms-muted">{{ hint() }}</small> }
        </div>
      </div>
      <cms-media-picker #picker (picked)="value.set($event.url)" />
    </div>
  `,
})
export class ImageField {
  readonly label = input('Image');
  readonly hint = input('');
  readonly value = model('');
}

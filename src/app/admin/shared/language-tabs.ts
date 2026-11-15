import { Component, input, model } from '@angular/core';
import { CONTENT_LOCALES, EditLocale } from '../models';

/**
 * Switches an editor between the English text and a translation. English is
 * the source and the fallback: translated fields left blank show English on
 * the site.
 */
@Component({
  selector: 'cms-language-tabs',
  template: `
    <div class="cms-tabs cms-lang-tabs" role="tablist" aria-label="Language">
      <button type="button" role="tab" [attr.aria-selected]="value() === 'en'" [class.active]="value() === 'en'"
              (click)="value.set('en')">English</button>
      @for (l of locales; track l.code) {
        <button type="button" role="tab" [attr.aria-selected]="value() === l.code" [class.active]="value() === l.code"
                (click)="value.set(l.code)">
          {{ l.label }}
          @if (!translated().includes(l.code)) { <span class="cms-lang-missing" title="Not translated yet">•</span> }
        </button>
      }
    </div>
  `,
})
export class LanguageTabs {
  readonly value = model<EditLocale>('en');
  /** Locales that already have some translated text. */
  readonly translated = input<string[]>([]);
  protected readonly locales = CONTENT_LOCALES;
}

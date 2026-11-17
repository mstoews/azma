import { Pipe, PipeTransform, inject } from '@angular/core';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';

/**
 * Marks CMS page/profile HTML as trusted so theme classes survive Angular's sanitizer.
 *
 * Safe only because that HTML is already cleaned: the API sanitizes it on save against
 * an allowlist (server/api/sanitize.go), and the bundled fallback is first-party. Never
 * use it for anything that has not been through that sanitizer.
 */
@Pipe({ name: 'trustedHtml' })
export class TrustedHtmlPipe implements PipeTransform {
  private readonly sanitizer = inject(DomSanitizer);
  transform(html: string): SafeHtml {
    return this.sanitizer.bypassSecurityTrustHtml(html);
  }
}

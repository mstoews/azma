import { Injectable, signal } from '@angular/core';

export type PageKind = 'home' | 'post' | 'page';

export interface PageState {
  kind: PageKind;
  id?: number;
  /** Id used in WordPress theme classes (postid-N, page-id-N). */
  cssId?: number | string;
  /** Image shown in the left aside. */
  image: string;
  imageAlt: string;
}

/** Shared state the route components publish so the layout (aside, body classes) can follow. */
@Injectable({ providedIn: 'root' })
export class PageStateService {
  readonly state = signal<PageState>({ kind: 'home', image: '', imageAlt: '' });
  readonly offcanvasOpen = signal(false);
}

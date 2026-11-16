import { Injectable, signal } from '@angular/core';

export type PageKind = 'home' | 'profile' | 'page';

export interface PageState {
  kind: PageKind;
  /** Id of the page or profile being shown, so the header can mark the current menu item. */
  id?: number;
}

/** What the routed component is showing, published for the layout (header, menu). */
@Injectable({ providedIn: 'root' })
export class PageStateService {
  readonly state = signal<PageState>({ kind: 'home' });
  readonly menuOpen = signal(false);
}

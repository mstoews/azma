import { Component, effect, inject } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';
import { SiteContentService } from '../content.service';
import { PageStateService } from '../page-state';
import { cssId } from '../site-data';

@Component({
  selector: 'app-home',
  imports: [RouterLink],
  templateUrl: './home.html',
})
export class Home {
  private readonly content = inject(SiteContentService);
  protected readonly profiles = this.content.profiles;
  protected readonly cssId = cssId;

  constructor() {
    const pageState = inject(PageStateService);
    const title = inject(Title);
    effect(() => {
      const s = this.content.settings();
      pageState.state.set({ kind: 'home', image: s.homeHeaderImage, imageAlt: '' });
      title.setTitle(`${s.siteName} – ${s.tagline}`);
    });
  }
}

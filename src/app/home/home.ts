import { Component, inject } from '@angular/core';
import { Title } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';
import { PageStateService } from '../page-state';
import { HOME_HEADER_IMAGE, PROFILES, SITE_NAME, SITE_TAGLINE } from '../site-data';

@Component({
  selector: 'app-home',
  imports: [RouterLink],
  templateUrl: './home.html',
})
export class Home {
  protected readonly profiles = PROFILES;

  constructor() {
    inject(PageStateService).state.set({ kind: 'home', image: HOME_HEADER_IMAGE, imageAlt: '' });
    inject(Title).setTitle(`${SITE_NAME} – ${SITE_TAGLINE}`);
  }
}

import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';
import { routes } from './app.routes';
import { SiteContentService } from './content.service';
import { SiteContent } from './site-data';

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [provideRouter(routes), provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();
  });

  it('renders the off-canvas navigation from bundled content', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const links = Array.from(fixture.nativeElement.querySelectorAll('#primary-nav-offcanvas a') as NodeListOf<HTMLElement>);
    expect(links.map((a) => a.textContent?.trim())).toEqual([
      'Who We Are', 'Our Expertise', 'Search Process', 'Vision &  Mission', 'Contact', '日本語',
    ]);
  });

  it('replaces bundled content with the CMS response', async () => {
    const svc = TestBed.inject(SiteContentService);
    const http = TestBed.inject(HttpTestingController);
    const done = svc.load();
    const body: SiteContent = {
      settings: { siteName: 'X', tagline: 't', homeDescription: 'd', homeHeaderImage: '', logo: '' },
      pages: [{ id: 9, legacyId: null, slug: 'new-page', title: 'New Page', hero: '', content: '<p>hi</p>' }],
      profiles: [],
      nav: [{ label: 'New Page', link: '/new-page', pageId: 9 }],
    };
    http.expectOne('/api/v1/site').flush(body);
    await done;
    expect(svc.source()).toBe('api');
    expect(svc.pages().map((p) => p.slug)).toEqual(['new-page']);
  });

  it('keeps bundled content when the CMS is unreachable', async () => {
    const svc = TestBed.inject(SiteContentService);
    const http = TestBed.inject(HttpTestingController);
    const done = svc.load();
    http.expectOne('/api/v1/site').error(new ProgressEvent('error'));
    await done;
    expect(svc.source()).toBe('bundled');
    expect(svc.profiles().length).toBe(11);
  });
});

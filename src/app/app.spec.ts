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

  const texts = (root: HTMLElement, sel: string) =>
    Array.from(root.querySelectorAll<HTMLElement>(sel)).map((a) => a.textContent?.trim());

  it('renders the header and menu navigation from bundled content', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    const pages = ['Who We Are', 'Our Expertise', 'Search Process', 'Vision &  Mission', 'Contact'];
    // Header: site pages inline; the external Japanese-site link sits apart, marked as Japanese.
    expect(texts(el, '.site-nav a')).toEqual(pages);
    expect(el.querySelector('.site-header-actions a[lang="ja"]')?.textContent?.trim()).toBe('日本語');
    // Mobile menu: Home, the pages, then the Japanese site.
    expect(texts(el, '#site-menu nav a')).toEqual(['Home', ...pages, '日本語']);
  });

  it('links the privacy policy from the footer and the consent banner', async () => {
    localStorage.removeItem('azma.consent.analytics');
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.site-footer a[href="/privacy-policy"]')).not.toBeNull();
    expect(el.querySelector('.site-consent a[href="/privacy-policy"]')).not.toBeNull();
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
    http.expectOne('/api/v1/site?lang=en').flush(body);
    await done;
    expect(svc.source()).toBe('api');
    expect(svc.pages().map((p) => p.slug)).toEqual(['new-page']);
  });

  it('keeps bundled content when the CMS is unreachable', async () => {
    const svc = TestBed.inject(SiteContentService);
    const http = TestBed.inject(HttpTestingController);
    const done = svc.load();
    http.expectOne('/api/v1/site?lang=en').error(new ProgressEvent('error'));
    await done;
    expect(svc.source()).toBe('bundled');
    expect(svc.profiles().length).toBe(11);
  });
});

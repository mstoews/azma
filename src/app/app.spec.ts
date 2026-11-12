import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { App } from './app';
import { routes } from './app.routes';

describe('App', () => {
  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [provideRouter(routes)],
    }).compileComponents();
  });

  it('renders the off-canvas navigation', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const links = Array.from(fixture.nativeElement.querySelectorAll('#primary-nav-offcanvas a') as NodeListOf<HTMLElement>);
    expect(links.map((a) => a.textContent?.trim())).toEqual([
      'Who We Are', 'Our Expertise', 'Search Process', 'Vision &  Mission', 'Contact', '日本語',
    ]);
  });
});

import { TestBed } from '@angular/core/testing';
import { ConsentService, GA_MEASUREMENT_ID } from './consent.service';

const gaScripts = () => document.head.querySelectorAll('script[src*="googletagmanager.com"]');
type W = Window & { dataLayer?: unknown[]; gtag?: unknown };

describe('ConsentService', () => {
  beforeEach(() => {
    localStorage.clear();
    gaScripts().forEach((s) => s.remove());
    delete (window as W).dataLayer;
    delete (window as W).gtag;
  });

  const create = () => TestBed.runInInjectionContext(() => new ConsentService());

  it('asks first and loads nothing before the visitor answers', () => {
    const c = create();
    c.init();
    expect(c.choice()).toBeNull();
    expect(c.bannerOpen()).toBe(true);
    expect(gaScripts().length).toBe(0);
    expect((window as W).dataLayer).toBeUndefined();
  });

  it('loads Analytics once on accept and remembers the choice', () => {
    const c = create();
    c.accept();
    c.init();
    expect(gaScripts().length).toBe(1);
    expect(gaScripts()[0].getAttribute('src')).toContain(GA_MEASUREMENT_ID);
    expect(c.bannerOpen()).toBe(false);
    expect(localStorage.getItem('azma.consent.analytics')).toBe('granted');
    // The config call is queued for gtag.js as an Arguments object.
    const config = ((window as W).dataLayer ?? []).map((a) => Array.from(a as ArrayLike<unknown>));
    expect(config).toContainEqual(['config', GA_MEASUREMENT_ID]);
  });

  it('loads Analytics on a later visit when consent was given before', () => {
    localStorage.setItem('azma.consent.analytics', 'granted');
    const c = create();
    expect(c.bannerOpen()).toBe(false);
    c.init();
    expect(gaScripts().length).toBe(1);
  });

  it('never loads Analytics after decline', () => {
    const c = create();
    c.decline();
    c.init();
    expect(gaScripts().length).toBe(0);
    expect(c.bannerOpen()).toBe(false);
    expect(create().choice()).toBe('denied');
  });

  it('can reopen the banner and close it again without changing the choice', () => {
    const c = create();
    c.decline();
    c.reopen();
    expect(c.bannerOpen()).toBe(true);
    c.dismiss();
    expect(c.bannerOpen()).toBe(false);
    expect(c.choice()).toBe('denied');
  });
});

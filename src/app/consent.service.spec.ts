import { TestBed } from '@angular/core/testing';
import { ConsentService, GA_MEASUREMENT_ID } from './consent.service';

const gaScripts = () => document.head.querySelectorAll('script[src*="googletagmanager.com"]');
type W = Window & { dataLayer?: unknown[]; gtag?: unknown };

describe('ConsentService', () => {
  const setGpc = (on: boolean | undefined) =>
    Object.defineProperty(navigator, 'globalPrivacyControl', { value: on, configurable: true });

  afterEach(() => setGpc(undefined));

  beforeEach(() => {
    localStorage.clear();
    document.cookie.split(';').forEach((c) => (document.cookie = `${c.split('=')[0].trim()}=; Max-Age=0; path=/`));
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

  describe('with Global Privacy Control', () => {
    beforeEach(() => setGpc(true));

    it('declines automatically: no banner, nothing loaded', () => {
      const c = create();
      c.init();
      expect(c.gpc()).toBe(true);
      expect(c.effective()).toBe('denied');
      expect(c.bannerOpen()).toBe(false);
      expect(gaScripts().length).toBe(0);
    });

    it('overrides an earlier accept without forgetting it', () => {
      localStorage.setItem('azma.consent.analytics', 'granted');
      const c = create();
      c.init();
      expect(gaScripts().length).toBe(0);
      expect(c.effective()).toBe('denied');
      expect(localStorage.getItem('azma.consent.analytics')).toBe('granted');
    });

    it('ignores accept', () => {
      const c = create();
      c.accept();
      expect(gaScripts().length).toBe(0);
      expect(c.choice()).toBeNull();
    });

    it('clears Analytics cookies left from an earlier visit', () => {
      document.cookie = '_ga=GA1.1.1; path=/';
      document.cookie = '_ga_ABC=GS1.1; path=/';
      document.cookie = 'other=1; path=/';
      create().init();
      expect(document.cookie).not.toMatch(/_ga/);
      expect(document.cookie).toContain('other=1');
    });

    it('lets the settings banner be opened and closed', () => {
      const c = create();
      c.reopen();
      expect(c.bannerOpen()).toBe(true);
      c.dismiss();
      expect(c.bannerOpen()).toBe(false);
    });
  });

  it('is unaffected when GPC is explicitly off', () => {
    setGpc(false);
    const c = create();
    expect(c.gpc()).toBe(false);
    expect(c.bannerOpen()).toBe(true);
  });
});

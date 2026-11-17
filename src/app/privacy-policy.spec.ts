import { PRIVACY_POLICY, PRIVACY_SLUG, resolvePage } from './privacy-policy';
import { SitePage } from './site-data';

const page = (slug: string, title = slug): SitePage => ({ id: 1, legacyId: null, slug, title, hero: '', content: '<p>x</p>' });

describe('resolvePage', () => {
  it('serves the built-in privacy policy when the CMS has none', () => {
    expect(resolvePage([page('contact')], PRIVACY_SLUG)).toBe(PRIVACY_POLICY);
  });

  it('prefers a CMS page with the privacy slug, so it can be edited there', () => {
    const cms = page(PRIVACY_SLUG, 'Our privacy notice');
    expect(resolvePage([cms], PRIVACY_SLUG)).toBe(cms);
  });

  it('finds ordinary pages and nothing for unknown slugs', () => {
    const contact = page('contact');
    expect(resolvePage([contact], 'contact')).toBe(contact);
    expect(resolvePage([contact], 'nope')).toBeUndefined();
  });

  it('describes what the site actually does', () => {
    const html = PRIVACY_POLICY.content;
    expect(html).toContain('Google Analytics');
    expect(html).toContain('Global Privacy Control');
    expect(html).toContain('mailto:company@azma-associates.com');
  });
});

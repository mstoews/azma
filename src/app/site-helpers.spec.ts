import { excerpt, firstEmail, profileLines, withoutRepeatedHeading } from './site-helpers';
import { Profile } from './site-data';

const profile = (content: string, excerptLines = ['鵜飼 重和', 'Managing Director', 'Singapore']): Profile => ({
  id: 1, legacyId: null, slug: 'x', title: 'Shigekazu Ukai', excerpt: excerptLines, thumb: '', hero: '', content,
});

describe('site helpers', () => {
  it('summarises the first paragraph or list item, not the headings', () => {
    expect(excerpt('<h3>Tokyo Office</h3><p>AZMA is a search firm.</p><p>More.</p>')).toBe('AZMA is a search firm.');
    expect(excerpt('<h3>1. Pre-search</h3><ul><li>Detailed discussion</li></ul>')).toBe('Detailed discussion');
    expect(excerpt('<p></p><p>Second</p>')).toBe('Second');
  });

  it('cuts long summaries at a word boundary', () => {
    const text = excerpt('<p>' + 'alpha beta gamma delta '.repeat(20) + '</p>', 40);
    expect(text.endsWith('…')).toBe(true);
    expect(text.length).toBeLessThanOrEqual(41);
    expect(text).not.toMatch(/\s…$/);
  });

  it('finds the first mailto address', () => {
    expect(firstEmail('<p><a href="mailto:company@example.com">mail</a></p>')).toBe('company@example.com');
    expect(firstEmail('<p>none</p>')).toBeNull();
  });

  it('reads the profile card lines', () => {
    expect(profileLines(profile(''))).toEqual({ nativeName: '鵜飼 重和', role: 'Managing Director', office: 'Singapore' });
    expect(profileLines(profile('', []))).toEqual({ nativeName: '', role: '', office: '' });
  });

  it('drops the leading heading only when it repeats the name', () => {
    const repeated = '<h2>鵜飼 重和<br>Managing Director<br>Singapore</h2><p>Bio</p>';
    expect(withoutRepeatedHeading(profile(repeated))).toBe('<p>Bio</p>');
    const other = '<h2>Career highlights</h2><p>Bio</p>';
    expect(withoutRepeatedHeading(profile(other))).toBe(other);
    expect(withoutRepeatedHeading(profile('<p>Bio</p>'))).toBe('<p>Bio</p>');
  });
});

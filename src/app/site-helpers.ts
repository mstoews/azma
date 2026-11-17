import { Profile } from './site-data';

/** Plain text of an HTML fragment (CMS content), whitespace collapsed. */
export function plainText(html: string): string {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  return (doc.body.textContent ?? '').replace(/\s+/g, ' ').trim();
}

/**
 * A short summary of an HTML fragment: the text of its first paragraph or list
 * item (so headings don't run into body text), cut at a word boundary.
 */
export function excerpt(html: string, max = 140): string {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const block = Array.from(doc.body.querySelectorAll('p, li')).find((el) => el.textContent?.trim());
  const text = (block?.textContent ?? doc.body.textContent ?? '').replace(/\s+/g, ' ').trim();
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  return cut.slice(0, Math.max(cut.lastIndexOf(' '), max * 0.6)).replace(/[\s,.;:–-]+$/, '') + '…';
}

/** First mailto address in an HTML fragment, if any. */
export function firstEmail(html: string): string | null {
  return /mailto:([^"'?\s>]+)/i.exec(html)?.[1] ?? null;
}

/** Card lines of a profile: Japanese name, role, office (any may be blank). */
export function profileLines(p: Profile): { nativeName: string; role: string; office: string } {
  const [nativeName = '', role = '', office = ''] = p.excerpt;
  return { nativeName: nativeName.trim(), role: role.trim(), office: office.trim() };
}

/**
 * Profile bodies imported from WordPress open with an <h2> that repeats the
 * Japanese name, role and office. The new layout shows those on the profile
 * card, so drop that heading — but only when it really is that repeat.
 */
export function withoutRepeatedHeading(p: Profile): string {
  const doc = new DOMParser().parseFromString(p.content, 'text/html');
  const first = doc.body.firstElementChild;
  const name = profileLines(p).nativeName;
  if (first?.tagName === 'H2' && name && (first.textContent ?? '').includes(name)) {
    first.remove();
    return doc.body.innerHTML;
  }
  return p.content;
}

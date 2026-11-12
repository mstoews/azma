import data from './data/site-data.json';

export interface Profile {
  id: number;
  slug: string;
  title: string;
  /** Lines of the archive excerpt (Japanese name, role, office). */
  excerpt: string[];
  /** Archive card image. */
  thumb: string;
  /** Full-size image shown in the aside on the profile page. */
  hero: string;
  /** Post body HTML, copied from the original site. */
  content: string;
}

export interface SitePage {
  id: number;
  slug: string;
  title: string;
  hero: string;
  content: string;
}

export interface NavItem {
  label: string;
  /** Internal router link, or undefined when `href` is external. */
  link?: string;
  href?: string;
  pageId: number;
}

export const SITE_NAME = 'AZMA & Associates';
export const SITE_TAGLINE = 'We are an APAC professional recruitment firm.';
export const HOME_DESCRIPTION = 'We are an Asia Pacific professional search firm.';
export const HOME_HEADER_IMAGE = '/wp-content/uploads/2021/07/cropped-cropped-max-bender-VmX3vmBecFE-unsplash-scaled-1.jpg';
export const LOGO = '/wp-content/uploads/2021/07/logo-3.png';

const slugify = (s: string) =>
  s.toLowerCase().replace(/&/g, ' ').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

export const PROFILES: Profile[] = data.posts.map((p) => ({ ...p, slug: slugify(p.title) }));
export const PAGES: SitePage[] = data.pages.map((p) => ({ ...p, slug: slugify(p.title) }));

export const NAV: NavItem[] = [
  ...PAGES.map((p) => ({ label: p.title, link: '/' + p.slug, pageId: p.id })),
  { label: '日本語', href: 'https://azma-associates.jp/', pageId: 467 },
];

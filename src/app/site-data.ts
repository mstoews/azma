import bundled from './data/site-data.json';

export interface Profile {
  /** Database id (or the WordPress id when running from the bundled fallback). */
  id: number;
  /** Original WordPress post id, kept so `/?p=N` links and theme CSS keep working. */
  legacyId: number | null;
  slug: string;
  title: string;
  /** Lines of the archive excerpt (Japanese name, role, office). */
  excerpt: string[];
  /** Archive card image. */
  thumb: string;
  /** Full-size image shown in the aside on the profile page. */
  hero: string;
  /** Post body HTML. */
  content: string;
}

export interface SitePage {
  id: number;
  legacyId: number | null;
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
  pageId?: number;
}

export interface SiteSettings {
  siteName: string;
  tagline: string;
  homeDescription: string;
  homeHeaderImage: string;
  logo: string;
}

export interface SiteContent {
  settings: SiteSettings;
  pages: SitePage[];
  profiles: Profile[];
  nav: NavItem[];
}

export const slugify = (s: string) =>
  s.toLowerCase().replace(/&/g, ' ').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

/** Id the WordPress theme CSS expects in body/article classes (page-id-176, postid-1). */
export const cssId = (x: { id: number; legacyId: number | null }) => x.legacyId ?? `cms-${x.id}`;

/**
 * The content the site was cloned with. Used only when the CMS API cannot be
 * reached, so the public site still renders rather than going blank.
 */
export function bundledContent(): SiteContent {
  const pages: SitePage[] = bundled.pages.map((p) => ({ ...p, legacyId: p.id, slug: slugify(p.title) }));
  return {
    settings: {
      siteName: 'AZMA & Associates',
      tagline: 'We are an APAC professional recruitment firm.',
      homeDescription: 'We are an Asia Pacific professional search firm.',
      homeHeaderImage: '/wp-content/uploads/2021/07/cropped-cropped-max-bender-VmX3vmBecFE-unsplash-scaled-1.jpg',
      logo: '/wp-content/uploads/2021/07/logo-3.png',
    },
    pages,
    profiles: bundled.posts.map((p) => ({ ...p, legacyId: p.id, slug: slugify(p.title) })),
    nav: [
      ...pages.map((p) => ({ label: p.title, link: '/' + p.slug, pageId: p.id })),
      { label: '日本語', href: 'https://azma-associates.jp/' },
    ],
  };
}

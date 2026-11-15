export interface AdminUser {
  id: string;
  email: string;
  name: string;
  role: string;
  disabled: boolean;
  lockedUntil: string | null;
  lastLoginAt: string | null;
  createdAt: string;
}

/** Languages content can be translated into; English is the source. Mirrors api.supportedLocales. */
export const CONTENT_LOCALES = [{ code: 'ja', label: '日本語' }] as const;
export type ContentLocale = (typeof CONTENT_LOCALES)[number]['code'];
export type EditLocale = 'en' | ContentLocale;

export interface PageTranslation {
  title: string;
  content: string;
}

export interface ProfileTranslation extends PageTranslation {
  excerpt: string[];
}

export interface SettingsTranslation {
  siteName: string;
  tagline: string;
  homeDescription: string;
}

export interface AdminPage {
  id: number;
  slug: string;
  title: string;
  hero: string;
  content: string;
  published: boolean;
  sortOrder: number;
  legacyWpId: number | null;
  createdAt: string;
  updatedAt: string;
  /** Only locales with a translation are present. */
  translations: Partial<Record<ContentLocale, PageTranslation>>;
}

export interface AdminProfile extends AdminPage {
  excerpt: string[];
  thumb: string;
  translations: Partial<Record<ContentLocale, ProfileTranslation>>;
}

/**
 * `translations` sets the locales it names (all fields blank removes one);
 * locales left out, or the whole field left out, are not changed.
 */
export type PageInput = Pick<AdminPage, 'slug' | 'title' | 'hero' | 'content' | 'published' | 'sortOrder'> & {
  translations?: Partial<Record<ContentLocale, PageTranslation>>;
};
export type ProfileInput = Pick<AdminPage, 'slug' | 'title' | 'hero' | 'content' | 'published' | 'sortOrder'> &
  Pick<AdminProfile, 'excerpt' | 'thumb'> & {
    translations?: Partial<Record<ContentLocale, ProfileTranslation>>;
  };

export interface AdminNavItem {
  id?: number;
  label: string;
  pageId: number | null;
  href: string;
  pageSlug?: string;
  pagePublished?: boolean;
  /** Translated labels by locale. */
  labels?: Partial<Record<ContentLocale, string>>;
}

export interface AdminSettings {
  siteName: string;
  tagline: string;
  homeDescription: string;
  homeHeaderImage: string;
  logo: string;
  updatedAt?: string;
  translations?: Partial<Record<ContentLocale, SettingsTranslation>>;
}

export interface MediaItem {
  id: number;
  url: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  width: number | null;
  height: number | null;
  alt: string;
  source: 'upload' | 'wordpress';
  createdAt: string;
}

export interface AuditEntry {
  id: number;
  userEmail: string;
  action: string;
  entity: string;
  entityId: string;
  createdAt: string;
  details?: unknown;
}

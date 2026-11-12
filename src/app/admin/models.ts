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
}

export interface AdminProfile extends AdminPage {
  excerpt: string[];
  thumb: string;
}

export type PageInput = Pick<AdminPage, 'slug' | 'title' | 'hero' | 'content' | 'published' | 'sortOrder'>;
export type ProfileInput = PageInput & Pick<AdminProfile, 'excerpt' | 'thumb'>;

export interface AdminNavItem {
  id?: number;
  label: string;
  pageId: number | null;
  href: string;
  pageSlug?: string;
  pagePublished?: boolean;
}

export interface AdminSettings {
  siteName: string;
  tagline: string;
  homeDescription: string;
  homeHeaderImage: string;
  logo: string;
  updatedAt?: string;
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

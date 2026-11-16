import { SitePage } from './site-data';

/** URL of the privacy policy: /privacy-policy. */
export const PRIVACY_SLUG = 'privacy-policy';

/**
 * Built-in privacy policy, shown at /privacy-policy unless the CMS has a page
 * with that slug (then the CMS page wins, so the text can be edited there).
 *
 * It describes what this site actually does; keep it in step with
 * ConsentService (Analytics, GPC), the self-hosted fonts and the hosting.
 */
export const PRIVACY_POLICY: SitePage = {
  id: -1,
  legacyId: null,
  slug: PRIVACY_SLUG,
  title: 'Privacy Policy',
  hero: '',
  content: `
<p>This policy explains what information this website collects when you visit it, why, and the choices you have. It covers this website only.</p>
<p><strong>Last updated:</strong> 16 November 2026</p>

<h2>Who we are</h2>
<p>This website is run by AZMA &amp; Associates:</p>
<ul>
<li>AZMA &amp; Associates (Japan) Limited / アズマ &amp; アソシエイツ株式会社, Morita Building 2F, 3-37-3 Honmachi, Shibuya, Tokyo 151-0071, Japan</li>
<li>AZMA &amp; Associates Pte. Ltd., 18 Robinson Road, #20-02 18 Robinson, Singapore 048547</li>
</ul>
<p>For any question about this policy or your information, email <a href="mailto:company@azma-associates.com">company@azma-associates.com</a>.</p>

<h2>Information we collect</h2>
<h3>Analytics, only if you accept</h3>
<p>With your consent, we use Google Analytics to understand how visitors use the site, for example which pages are viewed and how people arrive at them. Google Analytics sets cookies (<code>_ga</code> and <code>_ga_&lt;id&gt;</code>) and sends Google information such as the pages you visit, your browser and device type, and your approximate location. We use this only in aggregate, to improve the site.</p>
<p>Google Analytics is not loaded, and sets no cookies, until you choose “Accept analytics”. If you decline, or later change your mind, it stays off.</p>

<h3>Server logs</h3>
<p>The site is hosted on Google Cloud in Tokyo. Like any web server, the hosting service keeps technical request logs, which can include your IP address, browser, the page requested and the time. They are used to run the service and keep it secure.</p>

<h3>Emails you send us</h3>
<p>If you email us, we receive your email address and whatever you choose to include, and use it to reply to you.</p>

<h3>Settings stored in your browser</h3>
<p>The site remembers your analytics choice and your light/dark display setting in your browser's local storage. These stay on your device and are not sent to us.</p>

<h3>What we don't do</h3>
<ul>
<li>We don't use advertising or tracking cookies other than Google Analytics with your consent.</li>
<li>We don't sell your information.</li>
<li>Fonts and images are served from our own site, not from third-party services.</li>
</ul>

<h2>Your choices</h2>
<p>You can accept or decline analytics at any time with the “Cookie settings” link at the bottom of every page. If you decline after accepting, we delete the Google Analytics cookies from your browser.</p>
<p>If your browser sends a <a href="https://globalprivacycontrol.org/" rel="noopener">Global Privacy Control</a> signal, we treat it as declining analytics: Google Analytics is not loaded, and we don't ask.</p>
<p>You can also block or delete cookies in your browser's settings.</p>

<h2>Who we share information with</h2>
<p>We use Google as a service provider for analytics (only with your consent) and for hosting. Google may process this information outside Japan and Singapore. We don't share information from this website with anyone else, unless the law requires it.</p>

<h2>Your rights</h2>
<p>Depending on where you are, laws such as Japan's Act on the Protection of Personal Information and Singapore's Personal Data Protection Act give you rights over your personal information, including to ask what we hold about you, to have it corrected or deleted, and to withdraw your consent. To make a request, email <a href="mailto:company@azma-associates.com">company@azma-associates.com</a>.</p>

<h2>Changes to this policy</h2>
<p>If we change this policy, we will update it here and change the date at the top.</p>
`,
};

/** The page for a slug: the CMS page if there is one, else the built-in privacy policy. */
export function resolvePage(pages: SitePage[], slug: string): SitePage | undefined {
  return pages.find((p) => p.slug === slug) ?? (slug === PRIVACY_SLUG ? PRIVACY_POLICY : undefined);
}

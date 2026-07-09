import * as cheerio from 'cheerio';
import { NormalizedLmsCourse, NormalizedLmsStudent } from './contracts/lms-types';

const courseIdPattern = /[?&]wcid=([A-Za-z0-9_-]+)/i;
type CheerioRoot = ReturnType<typeof cheerio.load>;

interface SelectedOption {
  value?: string;
  text?: string;
}

export interface AdminUserListEntry {
  id: string;
  shortName: string;
  isSuperAdmin?: boolean;
  detailsPath?: string;
}

export function parseAdminCoursesHtml(
  html: string,
  keyPersonLmsUserId: string,
  keyPersonName: string,
): NormalizedLmsCourse[] {
  const $ = cheerio.load(html);
  const courses = new Map<string, NormalizedLmsCourse>();

  $('tr').each((_, row) => {
    const element = $(row);
    const cells = element
      .find('td')
      .toArray()
      .map((cell) => cleanText($(cell).text()));
    const links = element.find('a[href*="wcid="]').toArray();
    const lmsCourseId =
      links
        .map((link) => courseIdPattern.exec($(link).attr('href') ?? '')?.[1])
        .find((value): value is string => Boolean(value)) ??
      cells.find((value) => /^\d+$/.test(value));

    if (!lmsCourseId) return;

    const linkedName = links
      .map((link) => cleanText($(link).text()))
      .find((value) => isCourseName(value));
    const name = linkedName ?? cells.find((value) => isCourseName(value));

    if (!name) return;

    courses.set(lmsCourseId, {
      lmsCourseId,
      name,
      category: cells.find((value) => value !== lmsCourseId && value !== name),
      keyPersonLmsUserId,
      keyPersonName,
    });
  });

  return [...courses.values()];
}

/**
 * Extracts the admin's short/display name from the AdminLTE user-panel sidebar.
 *
 * The LMS renders it as:
 *   <div class="user-panel">
 *     <div class="info"><a class="d-block">developer</a></div>
 *   </div>
 *
 * This short name (e.g. "developer") is the SAME text shown in the keyperson
 * dropdown: <option value="92">developer</option>.
 * Using it in findAdminKeypersonId gives an exact match instead of a fragile
 * fuzzy match on the login username.
 */
export function parseAdminSidebarName(html: string): string | undefined {
  const $ = cheerio.load(html);
  const name = $('.user-panel .info a.d-block, .user-panel .info .d-block')
    .first()
    .text()
    .replace(/\s+/g, ' ')
    .trim();

  if (name && name.length >= 2 && !/^(#|-|admin|user|guest)$/i.test(name)) {
    return name;
  }
  return undefined;
}

/**
 * Parses the LMS /hr/view_users.php admin user table to find the row matching
 * the given login username. Returns the admin's numeric LMS ID and short name
 * (e.g. { id: "92", shortName: "developer" } for username "abdelrahman").
 *
 * This is the most reliable ID-discovery method — reads directly from the
 * admin table rather than doing any fuzzy name matching.
 * Only available if the logged-in admin has access to /hr/view_users.php.
 */
export function parseAdminFromUserList(
  html: string,
  loginUsername: string,
): AdminUserListEntry | undefined {
  const $ = cheerio.load(html);
  const username = loginUsername.toLowerCase().trim();

  let found: AdminUserListEntry | undefined;

  $('table tbody tr').each((_, row) => {
    const cells = $(row).find('td');
    if (cells.length < 3) return;

    const id = $(cells[0]).text().trim();
    const shortName = $(cells[1]).text().replace(/\s+/g, ' ').trim();
    const rowUsername = $(cells[2]).text().trim().toLowerCase();

    if (rowUsername === username && id && shortName) {
      const headers = $(row)
        .closest('table')
        .find('thead th')
        .toArray()
        .map((header) => normalizeFieldName($(header).text()));
      const fullAccessIndex = headers.findIndex(isFullAccessField);
      const fullAccessCell =
        fullAccessIndex >= 0 ? $(cells[fullAccessIndex]) : undefined;
      const isSuperAdmin =
        readFullAccessControl($, $(row)) ??
        (fullAccessCell ? readExactFullAccess(fullAccessCell.text()) : undefined);
      const detailsPath = $(row)
        .find('a[href]')
        .toArray()
        .map((link) => $(link).attr('href')?.trim())
        .find(
          (href): href is string =>
            Boolean(href) &&
            !/delete|remove/i.test(href!) &&
            /edit|update|details?|add[_-]?user|(?:user|admin)[^?]*\?[^#]*(?:id|admin_id|ad_id)=/i.test(
              href!,
            ),
        );

      found = {
        id,
        shortName,
        ...(isSuperAdmin === undefined ? {} : { isSuperAdmin }),
        ...(detailsPath ? { detailsPath } : {}),
      };
      return false; // break $.each
    }
  });

  return found;
}

function readFullAccessControl(
  $: CheerioRoot,
  element: ReturnType<CheerioRoot>,
): boolean | undefined {
  let result: boolean | undefined;

  element.find('[name]').each((_, control) => {
    const fieldName = normalizeFieldName($(control).attr('name') ?? '');
    if (!isFullAccessField(fieldName)) return;

    result = readExactFullAccess(String($(control).val() ?? ''));
    return false;
  });

  return result;
}

function readExactFullAccess(value: string): boolean | undefined {
  const normalized = value.trim();
  if (!normalized) return undefined;
  return normalized === '1';
}

function normalizeFieldName(value: string): string {
  return value.toLowerCase().replace(/[^a-z]/g, '');
}

function isFullAccessField(value: string): boolean {
  return value === 'fullaccess' || value === 'fullaccese';
}

export function parseAdminCourseIdsHtml(html: string): string[] {
  const $ = cheerio.load(html);
  const courseIds = new Set<string>();

  // Primary: standard anchor href attributes.
  $('a[href*="wcid="]').each((_, link) => {
    const id = courseIdPattern.exec($(link).attr('href') ?? '')?.[1];
    if (id) courseIds.add(id);
  });

  // Fallback: scan the entire raw HTML for every wcid= occurrence.
  // This catches course IDs embedded in JavaScript onclick handlers,
  // data-* attributes, form action URLs, and any other inline context
  // that the DOM selector above would miss (e.g. LMS pages that use
  // JS-driven navigation instead of plain <a href> links).
  for (const match of html.matchAll(/[?&]wcid=([A-Za-z0-9_-]+)/gi)) {
    if (match[1]) courseIds.add(match[1]);
  }

  return [...courseIds.values()];
}

export function parseAdminCourseEditHtml(
  html: string,
  lmsCourseId: string,
): NormalizedLmsCourse | undefined {
  const $ = cheerio.load(html);
  const keyPerson = readSelectedOption(
    $,
    'select[name="keyperson"], select#keyperson',
  );

  if (!keyPerson?.value) return undefined;

  const name =
    readControlText(
      $,
      'select[name="course"], select#course, input[name="course"], input#course',
    ) ??
    readControlText(
      $,
      'select[name="level"], select#level, input[name="level"], input#level',
    ) ??
    `Course ${lmsCourseId}`;
  const category = readControlText(
    $,
    'select[name="category"], select#category, select[name="cat"], select#cat, input[name="category"], input#category',
  );

  return {
    lmsCourseId,
    name,
    category,
    keyPersonLmsUserId: keyPerson.value,
    keyPersonName: keyPerson.text,
  };
}

function isCourseName(value: string): boolean {
  const lower = value.toLowerCase();

  return (
    value.length > 0 &&
    !/^\d+$/.test(value) &&
    !['students', 'add students', 'lms', 'edit', 'delete'].includes(lower)
  );
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function readControlText($: CheerioRoot, selector: string): string | undefined {
  const element = $(selector).first();
  if (element.length === 0) return undefined;

  if (element.is('select')) {
    return readSelectedOption($, selector)?.text;
  }

  const value = cleanText(String(element.val() ?? element.text()));
  return value || undefined;
}

function readSelectedOption(
  $: CheerioRoot,
  selector: string,
): SelectedOption | undefined {
  const select = $(selector).first();
  if (select.length === 0) return undefined;

  const value = cleanText(String(select.val() ?? ''));
  const selected = select.find('option[selected]').first();
  const matching = select
    .find('option')
    .filter((_, option) => $(option).attr('value') === value)
    .first();

  // The EACC LMS renders the currently-selected value as the FIRST <option>
  // without a `selected` attribute (browsers handle this automatically;
  // Cheerio may not). Fall back to the first option so we still read the
  // correct keyperson even when no explicit `selected` attribute is present.
  const option =
    selected.length > 0
      ? selected
      : matching.length > 0
        ? matching
        : select.find('option').first();

  const resolvedValue = cleanText(
    String(option.attr('value') ?? value ?? ''),
  );
  const text = cleanText(option.text());

  return resolvedValue || text
    ? {
        value: resolvedValue || undefined,
        text: text || undefined,
      }
    : undefined;
}

/**
 * Scans the keyperson dropdown on an /edit_course.php page to find which
 * option's display text best matches the given login username or admin name.
 *
 * The LMS stores admins by numeric ID in the keyperson column.  We know only
 * the login username (e.g. "abdelrahman"), but the dropdown contains entries
 * like `<option value="76">Abdelrahman Ali</option>`.  This function performs
 * a fuzzy match to discover that numeric ID ("76") so it can be used for
 * reliable keyperson comparisons without depending on exact string equality.
 *
 * Scoring (higher = more confident match):
 *  100 — exact match on username or name
 *   80 — option text starts with username (min 4 chars)
 *   70 — username starts with option text (min 4 chars)
 *   60 — option text contains username (min 4 chars)
 *   50 — option text starts with first word of admin name (min 4 chars)
 */
export function findAdminKeypersonId(
  html: string,
  loginUsername: string,
  adminName: string,
): string | undefined {
  const $ = cheerio.load(html);
  const select = $('select[name="keyperson"], select#keyperson').first();
  if (!select.length) return undefined;

  const username = loginUsername.toLowerCase().trim();
  const name = (adminName || '').toLowerCase().trim();
  const firstName = name.split(' ')[0] ?? '';

  interface Candidate {
    value: string;
    score: number;
  }
  const candidates: Candidate[] = [];

  select.find('option').each((_, option) => {
    const optText = cleanText($(option).text()).toLowerCase();
    const optValue = $(option).attr('value')?.trim();
    if (!optValue || !optText) return;

    let score = 0;
    if (optText === username || optText === name) {
      score = 100;
    } else if (username.length >= 4 && optText.startsWith(username)) {
      score = 80;
    } else if (username.length >= 4 && username.startsWith(optText)) {
      score = 70;
    } else if (username.length >= 4 && optText.includes(username)) {
      score = 60;
    } else if (firstName.length >= 4 && optText.startsWith(firstName)) {
      score = 50;
    }

    if (score > 0) candidates.push({ value: optValue, score });
  });

  candidates.sort((a, b) => b.score - a.score);
  return candidates[0]?.value;
}

export function parseAdminCourseStudentsHtml(
  html: string,
): NormalizedLmsStudent[] {
  const $ = cheerio.load(html);
  const students: NormalizedLmsStudent[] = [];

  // Find all table rows. The students are in a table with headers: ID, Name, Attendance, Grade
  $('table tbody tr').each((_, row) => {
    const cells = $(row).find('td');
    if (cells.length < 2) return;

    // First cell is ID (e.g. <td>8660</td>)
    const lmsUserId = $(cells[0]).text().trim();
    
    // Second cell contains the name inside an anchor tag
    // e.g. <td><a href='details.php?stid=8660'>test2</a>...
    const nameAnchor = $(cells[1]).find('a').first();
    const name = nameAnchor.text().trim();

    // Ensure we only grab valid student rows by verifying the ID is numeric
    if (lmsUserId && name && /^\d+$/.test(lmsUserId)) {
      students.push({ lmsUserId, name });
    }
  });

  return students;
}

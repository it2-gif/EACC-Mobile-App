import * as cheerio from 'cheerio';
import type { AnyNode } from 'domhandler';
import {
  NormalizedLmsCourse,
  NormalizedLmsStudent,
} from './contracts/lms-types';

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
  isManagerOperation?: boolean;
  isTechnicalSupport?: boolean;
  detailsPath?: string;
}

export interface AdminAccessFlags {
  isSuperAdmin?: boolean;
  isManagerOperation?: boolean;
  isTechnicalSupport?: boolean;
}

export interface AdminCourseTableSummary {
  totalCount?: number;
  visibleRowCount: number;
  isComplete: boolean;
}

export function parseAdminCourseTableSummary(
  html: string,
): AdminCourseTableSummary {
  const $ = cheerio.load(html);
  const visibleRowCount = findAdminCourseRows($).length;
  const totalCount = readAdminCourseTotalCount($);

  return {
    totalCount,
    visibleRowCount,
    isComplete: totalCount === undefined || visibleRowCount >= totalCount,
  };
}
export function parseAdminCoursesHtml(
  html: string,
  keyPersonLmsUserId: string,
  keyPersonName: string,
): NormalizedLmsCourse[] {
  const $ = cheerio.load(html);
  const rows = findAdminCourseRows($);
  const candidates: Array<{
    course: NormalizedLmsCourse;
    isOpenRow: boolean;
  }> = [];

  rows.each((_, row) => {
    const element = $(row);
    const cellElements = element.find('td').toArray();
    const cells = cellElements.map((cell) => cleanText($(cell).text()));
    const links = element.find('a[href*="wcid="]').toArray();
    const lmsCourseId =
      links
        .map((link) => courseIdPattern.exec($(link).attr('href') ?? '')?.[1])
        .find((value): value is string => Boolean(value)) ??
      cells.find((value) => /^\d+$/.test(value));

    if (!lmsCourseId) return;

    const headers = element
      .closest('table')
      .find('thead th')
      .toArray()
      .map((header) => normalizeFieldName($(header).text()));
    const departmentIndex = headers.findIndex(
      (header) => header === 'department' || header === 'category',
    );
    const courseIndex = headers.findIndex(
      (header) =>
        header === 'course' || header === 'coursename' || header === 'level',
    );
    const department =
      cells[departmentIndex >= 0 ? departmentIndex : 1]?.trim();
    const catalogCourseName = readMultilineCell(
      $,
      cellElements[courseIndex >= 0 ? courseIndex : 2],
    );
    const linkedName = links
      .map((link) => cleanText($(link).text()))
      .find((value) => isCourseName(value));
    const name =
      catalogCourseName ??
      linkedName ??
      cells.find((value) => isCourseName(value));

    if (!name) return;

    candidates.push({
      course: {
        lmsCourseId,
        name,
        category: department,
        keyPersonLmsUserId,
        keyPersonName,
      },
      isOpenRow: isOpenCourseRow(element),
    });
  });

  const rowsToUse = candidates.some((candidate) => candidate.isOpenRow)
    ? candidates.filter((candidate) => candidate.isOpenRow)
    : candidates;
  const courses = new Map<string, NormalizedLmsCourse>();
  for (const candidate of rowsToUse) {
    courses.set(candidate.course.lmsCourseId, candidate.course);
  }

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
    const normalizedShortName = shortName.toLowerCase().trim();

    if (
      (rowUsername === username || normalizedShortName === username) &&
      id &&
      shortName
    ) {
      const headers = $(row)
        .closest('table')
        .find('thead th')
        .toArray()
        .map((header) => normalizeFieldName($(header).text()));
      const fullAccessIndex = headers.findIndex(isFullAccessField);
      const managerOperationIndex = headers.findIndex(isManagerOperationField);
      const technicalSupportIndex = headers.findIndex(isTechnicalSupportField);
      const fullAccessCell =
        fullAccessIndex >= 0 ? $(cells[fullAccessIndex]) : undefined;
      const managerOperationCell =
        managerOperationIndex >= 0
          ? $(cells[managerOperationIndex])
          : undefined;
      const technicalSupportCell =
        technicalSupportIndex >= 0
          ? $(cells[technicalSupportIndex])
          : undefined;
      const isSuperAdmin =
        readFullAccessControl($, $(row)) ??
        (fullAccessCell
          ? readExactFullAccess(fullAccessCell.text())
          : undefined);
      const isManagerOperation =
        readManagerOperationControl($, $(row)) ??
        (managerOperationCell
          ? readExactEnabled(managerOperationCell.text())
          : undefined);
      const isTechnicalSupport =
        readTechnicalSupportControl($, $(row)) ??
        (technicalSupportCell
          ? readExactEnabled(technicalSupportCell.text())
          : undefined);
      const detailsPath = $(row)
        .find('a[href]')
        .toArray()
        .map((link) => $(link).attr('href')?.trim())
        .find(
          (href): href is string =>
            Boolean(href) && isAdminDetailsPath(href!, id),
        );

      found = {
        id,
        shortName,
        ...(isSuperAdmin === undefined ? {} : { isSuperAdmin }),
        ...(isManagerOperation === undefined ? {} : { isManagerOperation }),
        ...(isTechnicalSupport === undefined ? {} : { isTechnicalSupport }),
        ...(detailsPath ? { detailsPath } : {}),
      };
      return false; // break $.each
    }
  });

  return found;
}

export function parseAdminAccessFlagsHtml(html: string): AdminAccessFlags {
  const $ = cheerio.load(html);
  const isSuperAdmin =
    readFullAccessControl($, $.root()) ?? readInlineFullAccess(html);
  const isManagerOperation =
    readManagerOperationControl($, $.root()) ??
    readInlineManagerOperation(html);
  const isTechnicalSupport =
    readTechnicalSupportControl($, $.root()) ??
    readInlineTechnicalSupport(html);

  return {
    ...(isSuperAdmin === undefined ? {} : { isSuperAdmin }),
    ...(isManagerOperation === undefined ? {} : { isManagerOperation }),
    ...(isTechnicalSupport === undefined ? {} : { isTechnicalSupport }),
  };
}

function readManagerOperationControl(
  $: CheerioRoot,
  element: ReturnType<CheerioRoot>,
): boolean | undefined {
  let result: boolean | undefined;

  element.find('[name]').each((_, control) => {
    const fieldName = normalizeFieldName($(control).attr('name') ?? '');
    if (!isManagerOperationField(fieldName)) return;

    const value = readBooleanControlValue($, control);
    if (value === true) {
      result = true;
      return false;
    }
    if (value === false && result === undefined) {
      result = false;
    }
  });

  return result;
}

function readTechnicalSupportControl(
  $: CheerioRoot,
  element: ReturnType<CheerioRoot>,
): boolean | undefined {
  let result: boolean | undefined;

  element.find('[name]').each((_, control) => {
    const fieldName = normalizeFieldName($(control).attr('name') ?? '');
    if (!isTechnicalSupportField(fieldName)) return;

    const value = readBooleanControlValue($, control);
    if (value === true) {
      result = true;
      return false;
    }
    if (value === false && result === undefined) {
      result = false;
    }
  });

  return result;
}

function readFullAccessControl(
  $: CheerioRoot,
  element: ReturnType<CheerioRoot>,
): boolean | undefined {
  let result: boolean | undefined;

  element.find('[name]').each((_, control) => {
    const fieldName = normalizeFieldName($(control).attr('name') ?? '');
    if (!isFullAccessField(fieldName)) return;

    const value = readBooleanControlValue($, control);
    if (value === true) {
      result = true;
      return false;
    }
    if (value === false && result === undefined) {
      result = false;
    }
  });

  return result;
}

function readExactFullAccess(value: string): boolean | undefined {
  return readExactEnabled(value);
}

function readBooleanControlValue(
  $: CheerioRoot,
  control: AnyNode,
): boolean | undefined {
  const element = $(control);
  const tagName = control.type === 'tag' ? control.name.toLowerCase() : '';

  if (tagName === 'input') {
    const type = String(element.attr('type') ?? 'text').toLowerCase();
    if (type === 'checkbox' || type === 'radio') {
      return element.is('[checked]') || element.attr('checked') !== undefined
        ? readExactEnabled(String(element.val() ?? '1'))
        : false;
    }
  }

  if (tagName === 'select') {
    const selectedValue = element
      .find('option[selected]')
      .first()
      .attr('value');
    return selectedValue === undefined
      ? undefined
      : readExactEnabled(selectedValue);
  }

  return readExactEnabled(String(element.val() ?? ''));
}

function readExactEnabled(value: string): boolean | undefined {
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

function isManagerOperationField(value: string): boolean {
  return (
    value === 'moperation' ||
    value === 'mop' ||
    value === 'operationmanager' ||
    value === 'manageroperation' ||
    value === 'managerop'
  );
}

function isTechnicalSupportField(value: string): boolean {
  return value === 'tec' || value === 'tech' || value === 'technicalsupport';
}

function isAdminDetailsPath(href: string, adminId: string): boolean {
  if (/delete|remove/i.test(href)) return false;

  const hasAdminId = new RegExp(
    `(?:[?&]|\\b)(?:id|admin_id|ad_id|user_id|uid|auid|admin|user)=${escapeRegex(
      adminId,
    )}(?:\\b|&|#|$)`,
    'i',
  ).test(href);
  const looksEditable =
    /edit|update|details?|add[_-]?user|(?:user|admin)/i.test(href);

  return hasAdminId && looksEditable;
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function readInlineFullAccess(html: string): boolean | undefined {
  return readInlineBooleanFlag(html, ['fullaccess', 'fullaccese']);
}

function readInlineManagerOperation(html: string): boolean | undefined {
  return readInlineBooleanFlag(html, [
    'moperation',
    'm_op',
    'operation_manager',
    'manageroperation',
    'manager_op',
  ]);
}

function readInlineTechnicalSupport(html: string): boolean | undefined {
  return readInlineBooleanFlag(html, [
    'tec',
    'tech',
    'technical_support',
    'technicalsupport',
  ]);
}

function readInlineBooleanFlag(
  html: string,
  compactKeys: string[],
): boolean | undefined {
  const normalized = html.toLowerCase();

  for (const key of compactKeys) {
    const pattern = new RegExp(
      `(?:\\[\\s*)?["']?${key}["']?\\s*\\]?\\s*(?:=|:|=>)\\s*["']?([01])["']?`,
      'i',
    );
    const value = pattern.exec(normalized)?.[1];
    if (value === '1') return true;
    if (value === '0') return false;
  }

  return undefined;
}

export function parseAdminCourseIdsHtml(html: string): string[] {
  const $ = cheerio.load(html);
  const rows = findAdminCourseRows($);
  const rowCandidates: Array<{ id: string; isOpenRow: boolean }> = [];

  rows.each((_, row) => {
    const element = $(row);
    const id =
      element
        .find('a[href*="wcid="]')
        .toArray()
        .map((link) => courseIdPattern.exec($(link).attr('href') ?? '')?.[1])
        .find((value): value is string => Boolean(value)) ??
      element
        .find('td')
        .toArray()
        .map((cell) => cleanText($(cell).text()))
        .find((value) => /^\d+$/.test(value));

    if (id) rowCandidates.push({ id, isOpenRow: isOpenCourseRow(element) });
  });

  if (rowCandidates.some((candidate) => candidate.isOpenRow)) {
    return [
      ...new Set(
        rowCandidates
          .filter((candidate) => candidate.isOpenRow)
          .map((candidate) => candidate.id),
      ),
    ];
  }

  if (rowCandidates.length > 0) {
    return [...new Set(rowCandidates.map((candidate) => candidate.id))];
  }

  const openCourses = $('#Open');
  const linkSelector =
    openCourses.length > 0 ? '#Open a[href*="wcid="]' : 'a[href*="wcid="]';
  const courseIds = new Set<string>();

  // Primary: standard anchor href attributes.
  $(linkSelector).each((_, link) => {
    const id = courseIdPattern.exec($(link).attr('href') ?? '')?.[1];
    if (id) courseIds.add(id);
  });

  // Fallback: scan the scoped raw HTML for every wcid= occurrence.
  const scopedHtml = openCourses.length > 0 ? (openCourses.html() ?? '') : html;
  for (const match of scopedHtml.matchAll(/[?&]wcid=([A-Za-z0-9_-]+)/gi)) {
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
  const teacherOption = readSelectedOption(
    $,
    [
      'select[name="teacher"]',
      'select#teacher',
      'select[name="teacher_id"]',
      'select#teacher_id',
      'select[name="teacherid"]',
      'select#teacherid',
      'select[name="te_id"]',
      'select#te_id',
      'select[name="t_id"]',
      'select#t_id',
    ].join(', '),
  );
  const teacherLmsUserId =
    teacherOption?.value ??
    readControlValue(
      $,
      [
        'input[name="teacher_id"]',
        'input#teacher_id',
        'input[name="teacherid"]',
        'input#teacherid',
        'input[name="te_id"]',
        'input#te_id',
        'input[name="t_id"]',
        'input#t_id',
      ].join(', '),
    );
  const teacherName = readControlText(
    $,
    [
      'select[name="teacher"]',
      'select#teacher',
      'select[name="teacher_id"]',
      'select#teacher_id',
      'select[name="teacherid"]',
      'select#teacherid',
      'select[name="te_id"]',
      'select#te_id',
      'select[name="t_id"]',
      'select#t_id',
      'input[name="teacher"]',
      'input#teacher',
      'input[name="teacher_name"]',
      'input#teacher_name',
    ].join(', '),
  );

  return {
    lmsCourseId,
    name,
    category,
    teacherLmsUserId,
    teacherName: isLikelyTeacherName(teacherName, teacherLmsUserId)
      ? teacherName
      : undefined,
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

function readAdminCourseTotalCount($: CheerioRoot): number | undefined {
  const pageText = cleanText($('body').text());
  const totalClasses = /\bTotal\s+Classes\s*:\s*(\d+)\b/i.exec(pageText)?.[1];
  const dataTablesTotal =
    /\bShowing\s+\d+\s+to\s+\d+\s+of\s+(\d+)\s+entries\b/i.exec(pageText)?.[1];
  const value = totalClasses ?? dataTablesTotal;
  return value ? Number(value) : undefined;
}
function findAdminCourseRows($: CheerioRoot): ReturnType<CheerioRoot> {
  const tableRows = $('#example2 tbody tr');
  if (tableRows.length > 0) return tableRows;

  const openRows = $('#Open tr');
  if (openRows.length > 0) return openRows;

  return $('tr');
}

function isOpenCourseRow(element: ReturnType<CheerioRoot>): boolean {
  const marker = [
    element.attr('class') ?? '',
    element.attr('style') ?? '',
    element.attr('data-status') ?? '',
    element.attr('data-course-status') ?? '',
  ]
    .join(' ')
    .toLowerCase();

  return (
    /\b(open|active|working|success|table-success)\b/.test(marker) ||
    marker.includes('background-color: green') ||
    marker.includes('background: green') ||
    marker.includes('#c3e6cb') ||
    marker.includes('#d4edda') ||
    marker.includes('rgb(195, 230, 203)') ||
    marker.includes('rgb(212, 237, 218)') ||
    marker.includes('lightgreen')
  );
}

function readMultilineCell(
  $: CheerioRoot,
  cell: AnyNode | undefined,
): string | undefined {
  if (!cell) return undefined;

  const clone = $(cell).clone();
  clone.find('br').replaceWith(' | ');
  const value = cleanText(clone.text())
    .replace(/\s*\|\s*/g, ' - ')
    .replace(/\s+-\s+-\s+/g, ' - ');

  return isCourseName(value) ? value : undefined;
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

function readControlValue(
  $: CheerioRoot,
  selector: string,
): string | undefined {
  const element = $(selector).first();
  if (element.length === 0) return undefined;

  const value = cleanText(String(element.val() ?? ''));
  return value || undefined;
}

function isLikelyTeacherName(
  value: string | undefined,
  teacherLmsUserId: string | undefined,
): value is string {
  const trimmed = value?.trim();
  if (!trimmed) return false;
  if (teacherLmsUserId && trimmed === teacherLmsUserId.trim()) return false;
  return !/^\d+$/.test(trimmed);
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

  const resolvedValue = cleanText(String(option.attr('value') ?? value ?? ''));
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

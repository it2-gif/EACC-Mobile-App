import * as cheerio from 'cheerio';
import { NormalizedLmsCourse } from './contracts/lms-types';

const courseIdPattern = /[?&]wcid=([A-Za-z0-9_-]+)/i;
type CheerioRoot = ReturnType<typeof cheerio.load>;

interface SelectedOption {
  value?: string;
  text?: string;
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

export function parseAdminCourseIdsHtml(html: string): string[] {
  const $ = cheerio.load(html);
  const courseIds = new Set<string>();

  $('a[href*="wcid="]').each((_, link) => {
    const id = courseIdPattern.exec($(link).attr('href') ?? '')?.[1];
    if (id) courseIds.add(id);
  });

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
  const option = selected.length > 0 ? selected : matching;
  const text = cleanText(option.text());

  return value || text
    ? {
        value: value || undefined,
        text: text || undefined,
      }
    : undefined;
}

import * as cheerio from 'cheerio';
import { NormalizedLmsCourse } from './contracts/lms-types';

const courseIdPattern = /[?&]wcid=([A-Za-z0-9_-]+)/i;

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

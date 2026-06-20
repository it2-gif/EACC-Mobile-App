import * as cheerio from 'cheerio';
import { NormalizedLmsStudent } from './contracts/lms-types';
import { InvalidLmsResponseError } from './eacc-lms.errors';

export function parseTeacherCourseStudentsHtml(
  html: string,
): NormalizedLmsStudent[] {
  const $ = cheerio.load(html);
  const studentsTab = $('#Students');

  if (studentsTab.length !== 1) {
    throw new InvalidLmsResponseError(
      'The LMS course details page did not contain a Students tab.',
    );
  }

  return studentsTab
    .find('tbody tr')
    .toArray()
    .map((row) => {
      const cells = $(row).find('td').toArray();
      const lmsUserId = cleanText($(cells[0]).text());
      const name = cleanText(
        $(cells[1]).clone().children().remove().end().text(),
      );

      if (!lmsUserId || !name) {
        throw new InvalidLmsResponseError(
          'The LMS course student row had an unexpected format.',
        );
      }

      return { lmsUserId, name };
    });
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

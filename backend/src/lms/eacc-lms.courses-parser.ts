import * as cheerio from 'cheerio';
import { NormalizedLmsCourse } from './contracts/lms-types';
import { InvalidLmsResponseError } from './eacc-lms.errors';

const courseIdPattern = /[?&]wcid=([A-Za-z0-9_-]+)/i;

export function parseStudentCoursesHtml(html: string): NormalizedLmsCourse[] {
  const $ = cheerio.load(html);
  const openCourses = $('#Open');

  if (openCourses.length !== 1) {
    throw new InvalidLmsResponseError();
  }

  return openCourses
    .find('a[href*="wcid="]')
    .toArray()
    .map((link) => {
      const element = $(link);
      const href = element.attr('href') ?? '';
      const idMatch = courseIdPattern.exec(href);
      const card = element.find('.card').first();
      const labels = card
        .find('.d-flex.flex-column span')
        .toArray()
        .map((span) => cleanText($(span).text()))
        .filter((value) => value.length > 0);

      const lmsCourseId = idMatch?.[1];
      const category = labels[0];
      const name = labels[1];

      if (!lmsCourseId || !name) {
        throw new InvalidLmsResponseError();
      }

      return {
        lmsCourseId,
        name,
        category,
      };
    });
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

import * as cheerio from 'cheerio';
import { LmsUserRole, NormalizedLmsUser } from './contracts/lms-types';
import { InvalidLmsResponseError } from './eacc-lms.errors';

const teacherIdPattern = /teachers\/([A-Za-z0-9_-]+)[/.-]/i;

export function parseTeacherDashboardHtml(
  html: string,
  role: LmsUserRole,
): NormalizedLmsUser {
  if (role !== 'teacher') {
    throw new InvalidLmsResponseError();
  }

  const $ = cheerio.load(html);
  const name = $('.user-panel .info a, .user-panel .info .d-block')
    .toArray()
    .map((element) => $(element).text().replace(/\s+/g, ' ').trim())
    .find((text) => text.length > 0);
  const imageSrc = $('.user-panel img').attr('src') ?? '';
  const lmsUserId =
    teacherIdPattern.exec(imageSrc)?.[1] ??
    teacherIdPattern.exec(html)?.[1] ??
    name?.replace(/\s+/g, '_').toLowerCase();

  if (!name || !lmsUserId) {
    throw new InvalidLmsResponseError(
      'The LMS teacher dashboard did not contain a recognizable teacher name.',
    );
  }

  return {
    lmsUserId,
    role,
    name,
    courses: [],
  };
}

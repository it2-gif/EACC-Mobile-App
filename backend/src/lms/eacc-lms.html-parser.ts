import * as cheerio from 'cheerio';
import { LmsUserRole, NormalizedLmsUser } from './contracts/lms-types';
import { InvalidLmsResponseError } from './eacc-lms.errors';

const studentWelcomePattern = /Welcome\s+(.+?)\s*\/\s*ID:\s*([A-Za-z0-9_-]+)/i;
const compactWelcomePattern = /Welcome\s+(.+?)\s*ID:\s*([A-Za-z0-9_-]+)/i;

export function parseLmsDashboardHtml(
  html: string,
  role: LmsUserRole,
): NormalizedLmsUser {
  if (role !== 'student') {
    throw new InvalidLmsResponseError();
  }

  const $ = cheerio.load(html);
  const bodyText = $('body').text().replace(/\s+/g, ' ').trim();
  const welcomeText = $(
    'h1, h2, h3, h4, h5, h6, .info a, .user-panel .info a, body',
  )
    .toArray()
    .map((element) => $(element).text().replace(/\s+/g, ' ').trim())
    .find(
      (text) =>
        studentWelcomePattern.test(text) || compactWelcomePattern.test(text),
    );

  if (!welcomeText) {
    throw new InvalidLmsResponseError(
      `The LMS student dashboard did not contain a recognizable welcome line. Body preview: ${bodyText.slice(0, 220)}`,
    );
  }

  const match =
    studentWelcomePattern.exec(welcomeText) ??
    compactWelcomePattern.exec(welcomeText);
  if (!match) {
    throw new InvalidLmsResponseError(
      `The LMS welcome line had an unexpected format: ${welcomeText.slice(0, 220)}`,
    );
  }

  const name = match[1]?.replace(/\s+/g, ' ').trim();
  const lmsUserId = match[2]?.trim();

  if (!name || !lmsUserId) throw new InvalidLmsResponseError();

  return {
    lmsUserId,
    role,
    name,
    courses: [],
  };
}

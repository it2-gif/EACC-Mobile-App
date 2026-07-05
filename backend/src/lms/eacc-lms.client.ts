import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Environment } from '../config/environment';
import { LmsClient } from './contracts/lms-client';
import {
  LmsLoginCredentials,
  LmsUserRole,
  NormalizedLmsCourse,
  NormalizedLmsUser,
} from './contracts/lms-types';
import {
  InvalidLmsCredentialsError,
  LmsUnavailableError,
} from './eacc-lms.errors';
import {
  parseAdminCourseEditHtml,
  parseAdminCourseIdsHtml,
  parseAdminCoursesHtml,
} from './eacc-lms.admin-courses-parser';
import { parseTeacherCourseStudentsHtml } from './eacc-lms.course-students-parser';
import { parseStudentCoursesHtml } from './eacc-lms.courses-parser';
import { parseLmsDashboardHtml } from './eacc-lms.html-parser';
import { parseTeacherDashboardHtml } from './eacc-lms.teacher-parser';
import { parseLmsResponse } from './eacc-lms.parser';

const loginPaths: Record<LmsUserRole, string> = {
  student: '/members/login_1.php',
  teacher: '/teacher/login_1.php',
  admin: '/login_1.php',
};

const dashboardPaths: Record<LmsUserRole, string> = {
  student: '/members/',
  teacher: '/teacher/index.php',
  admin: '/front.php',
};

@Injectable()
export class EaccLmsClient implements LmsClient {
  constructor(private readonly config: ConfigService<Environment, true>) {}

  async authenticate(
    credentials: LmsLoginCredentials,
  ): Promise<NormalizedLmsUser> {
    const baseUrl = this.config.get('LMS_BASE_URL', { infer: true });
    const timeout = this.config.get('LMS_REQUEST_TIMEOUT_MS', { infer: true });
    const endpoint = new URL(loginPaths[credentials.role], baseUrl);
    const sessionCookie = await this.createSession(baseUrl, timeout);
    const body = new URLSearchParams({
      ty: credentials.role,
      username: credentials.username,
      inputPassword: credentials.password,
    });

    let response: Response;

    try {
      response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          accept: 'text/html,application/json',
          'content-type': 'application/x-www-form-urlencoded',
          ...(sessionCookie ? { cookie: sessionCookie } : {}),
        },
        body,
        redirect: 'follow',
        signal: AbortSignal.timeout(timeout),
      });
    } catch {
      throw new LmsUnavailableError();
    }

    const responseText = await response.text();

    if (
      response.url.includes('login=failed') ||
      response.status === 401 ||
      response.status === 403 ||
      responseText.includes('Username Not Found')
    ) {
      throw new InvalidLmsCredentialsError();
    }

    if (!response.ok) {
      throw new LmsUnavailableError();
    }

    const jsonPayload = tryParseJson(responseText);
    if (jsonPayload !== undefined) {
      return parseLmsResponse(jsonPayload.value, credentials.role);
    }

    const dashboardUrl = new URL(dashboardPaths[credentials.role], baseUrl);
    const user = await this.loadDashboard(
      dashboardUrl,
      mergeSessionCookie(sessionCookie, response.headers),
      timeout,
      credentials.role,
      credentials,
      responseText,
    );

    if (credentials.role === 'student' || credentials.role === 'teacher') {
      const coursesHtml = await this.loadAuthenticatedHtml(
        new URL(
          credentials.role === 'student' ? '/members/lms' : '/teacher/lms',
          baseUrl,
        ),
        mergeSessionCookie(sessionCookie, response.headers),
        timeout,
      );

      const courses = parseStudentCoursesHtml(coursesHtml);

      if (credentials.role === 'teacher') {
        const coursesWithStudents = await Promise.all(
          courses.map(async (course) => {
            const detailsHtml = await this.loadAuthenticatedHtml(
              new URL(
                `/teacher/lms_details.php?wcid=${encodeURIComponent(course.lmsCourseId)}`,
                baseUrl,
              ),
              mergeSessionCookie(sessionCookie, response.headers),
              timeout,
            );

            return {
              ...course,
              students: parseTeacherCourseStudentsHtml(detailsHtml),
            };
          }),
        );

        return {
          ...user,
          courses: coursesWithStudents,
        };
      }

      return {
        ...user,
        courses,
      };
    }

    return user;
  }

  private async createSession(
    baseUrl: string,
    timeout: number,
  ): Promise<string> {
    let response: Response;

    try {
      response = await fetch(new URL('/login.php', baseUrl), {
        headers: { accept: 'text/html' },
        signal: AbortSignal.timeout(timeout),
      });
    } catch {
      throw new LmsUnavailableError();
    }

    if (!response.ok) throw new LmsUnavailableError();

    return extractSessionCookie(response.headers) ?? '';
  }

  private async loadDashboard(
    url: URL,
    sessionCookie: string,
    timeout: number,
    role: LmsUserRole,
    credentials?: LmsLoginCredentials,
    loginResponseHtml = '',
  ): Promise<NormalizedLmsUser> {
    const html = await this.loadAuthenticatedHtml(url, sessionCookie, timeout);

    if (role === 'student') {
      return parseLmsDashboardHtml(html, role);
    }

    if (role === 'teacher') {
      return parseTeacherDashboardHtml(html, role);
    }

    if (role === 'admin') {
      const admin = parseAdminIdentity(
        credentials!.username,
        `${loginResponseHtml}\n${html}`,
      );

      return admin.isSuperAdmin
        ? admin
        : {
            ...admin,
            courses: await this.loadAdminKeyPersonCourses(
              url.origin,
              sessionCookie,
              timeout,
              html,
              admin,
            ),
          };
    }

    throw new LmsUnavailableError();
  }

  private async loadAuthenticatedHtml(
    url: URL,
    sessionCookie: string,
    timeout: number,
  ): Promise<string> {
    let response: Response;

    try {
      response = await fetch(url, {
        headers: {
          accept: 'text/html',
          ...(sessionCookie ? { cookie: sessionCookie } : {}),
        },
        redirect: 'follow',
        signal: AbortSignal.timeout(timeout),
      });
    } catch {
      throw new LmsUnavailableError();
    }

    const html = await response.text();
    if (!response.ok || looksLikeLoginPage(html)) {
      throw new InvalidLmsCredentialsError();
    }

    return html;
  }

  private async loadAdminKeyPersonCourses(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    dashboardHtml: string,
    admin: NormalizedLmsUser,
  ): Promise<NormalizedLmsCourse[]> {
    const dashboardCourses = parseAdminCoursesHtml(
      dashboardHtml,
      admin.lmsUserId,
      admin.name,
    );
    const candidateIds = uniqueStrings([
      ...dashboardCourses.map((course) => course.lmsCourseId),
      ...parseAdminCourseIdsHtml(dashboardHtml),
      ...readConfiguredKeyPersonCourseIds(admin.lmsUserId),
    ]);

    if (candidateIds.length === 0) {
      return dashboardCourses;
    }

    const verifiedCourses: NormalizedLmsCourse[] = [];

    for (const courseId of candidateIds) {
      const courseUrl = new URL('/edit_course.php', baseUrl);
      courseUrl.searchParams.set('wcid', courseId);

      try {
        const html = await this.loadAuthenticatedHtml(
          courseUrl,
          sessionCookie,
          timeout,
        );
        const course = parseAdminCourseEditHtml(html, courseId);

        if (course?.keyPersonLmsUserId === admin.lmsUserId) {
          verifiedCourses.push({
            ...course,
            keyPersonName: course.keyPersonName ?? admin.name,
          });
        }
      } catch {
        // Some candidate course IDs may not be visible in this LMS admin session.
      }
    }

    return verifiedCourses.length > 0
      ? uniqueCourses(verifiedCourses)
      : dashboardCourses;
  }
}

function readConfiguredKeyPersonCourseIds(lmsUserId: string): string[] {
  const raw = process.env.LMS_KEY_PERSON_COURSE_IDS;
  if (!raw) {
    return [];
  }

  return raw.split(/[;\n]+/).flatMap((entry) => {
    const [entryLmsUserId, courseIds] = entry.split(':');

    if (entryLmsUserId?.trim() !== lmsUserId || !courseIds) {
      return [];
    }

    return courseIds
      .split(/[|,\s]+/)
      .map((courseId) => courseId.trim())
      .filter(Boolean);
  });
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}

function uniqueCourses(courses: NormalizedLmsCourse[]): NormalizedLmsCourse[] {
  const byId = new Map<string, NormalizedLmsCourse>();

  for (const course of courses) {
    byId.set(course.lmsCourseId, course);
  }

  return [...byId.values()];
}

function tryParseJson(value: string): { value: unknown } | undefined {
  try {
    return { value: JSON.parse(value) as unknown };
  } catch {
    return undefined;
  }
}

function parseAdminIdentity(username: string, html: string): NormalizedLmsUser {
  const trimmed = username.trim().toLowerCase();
  const lmsUserId =
    readAdminIdentityValue(html, [
      'admin_id',
      'ad_id',
      'adminId',
      'user_id',
      'userId',
    ]) ??
    readAdminIdOverride(trimmed) ??
    trimmed;
  const displayName =
    readAdminIdentityValue(html, [
      'admin_shortname',
      'adminShortname',
      'short_name',
      'shortName',
      'shortname',
      'username',
      'admin_name',
      'ad_name',
    ]) ?? trimmed;

  return {
    lmsUserId,
    role: 'admin',
    name: displayName,
    isSuperAdmin: hasAdminFullAccess(html),
    courses: [],
  };
}

function readAdminIdOverride(username: string): string | undefined {
  const overrides = process.env.LMS_ADMIN_ID_OVERRIDES;
  if (!overrides) {
    return undefined;
  }

  for (const entry of overrides.split(',')) {
    const [rawUsername, rawLmsId] = entry.split(':');
    const normalizedUsername = rawUsername?.trim().toLowerCase();
    const lmsId = rawLmsId?.trim();

    if (normalizedUsername === username && lmsId) {
      return lmsId;
    }
  }

  return undefined;
}

function readAdminIdentityValue(
  html: string,
  keys: string[],
): string | undefined {
  for (const key of keys) {
    const escapedKey = escapeRegex(key);
    const patterns = [
      new RegExp(`["']${escapedKey}["']\\s*:\\s*["']?([^"',}\\s]+)`, 'i'),
      new RegExp(`\\b${escapedKey}\\b\\s*(?:=|:|=>)\\s*["']?([^"',}\\s<>]+)`, 'i'),
      new RegExp(
        `name=["']${escapedKey}["'][^>]*value=["']?([^"'>\\s]+)`,
        'i',
      ),
    ];

    for (const pattern of patterns) {
      const value = pattern.exec(html)?.[1]?.trim();
      if (value) {
        return value;
      }
    }
  }

  return undefined;
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function hasAdminFullAccess(html: string): boolean {
  const normalized = html.toLowerCase();

  const truthyValue = '(?:1|true|yes|y|on)';
  const fullAccessKeys = [
    'full[_-]?access',
    'fullaccess',
    'is[_-]?super[_-]?admin',
    'super[_-]?admin',
  ];

  const directPatterns = fullAccessKeys.flatMap((key) => [
    new RegExp(`\\b${key}\\b\\s*(?:=|:|=>)\\s*["']?${truthyValue}["']?`),
    new RegExp(`["']${key}["']\\s*:\\s*["']?${truthyValue}["']?`),
    new RegExp(`${key}["'\\s:=]+${truthyValue}`),
  ]);

  if (directPatterns.some((pattern) => pattern.test(normalized))) {
    return true;
  }

  const inputPattern =
    /<input[^>]+name\s*=\s*["']([^"']+)["'][^>]*value\s*=\s*["']?([^"'\s>]+)["']?[^>]*>/g;

  for (const match of normalized.matchAll(inputPattern)) {
    const key = match[1].replace(/[-_\s]/g, '');
    const value = match[2].trim();

    if (
      ['fullaccess', 'issuperadmin', 'superadmin'].includes(key) &&
      ['1', 'true', 'yes', 'y', 'on'].includes(value)
    ) {
      return true;
    }
  }

  return false;
}

function extractSessionCookie(headers: Headers): string | undefined {
  const rawSetCookie =
    typeof headers.getSetCookie === 'function'
      ? headers.getSetCookie()
      : headers.get('set-cookie')
        ? [headers.get('set-cookie')!]
        : [];

  const sessionCookie = rawSetCookie.find((cookie) =>
    cookie.startsWith('PHPSESSID='),
  );

  return sessionCookie?.split(';', 1)[0];
}

function mergeSessionCookie(currentCookie: string, headers: Headers): string {
  return extractSessionCookie(headers) ?? currentCookie;
}

function looksLikeLoginPage(html: string): boolean {
  const normalized = html.toLowerCase();

  return (
    normalized.includes('name="inputpassword"') ||
    normalized.includes('username not found') ||
    normalized.includes('wrap-login100')
  );
}

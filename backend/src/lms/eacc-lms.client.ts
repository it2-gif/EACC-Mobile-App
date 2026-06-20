import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Environment } from '../config/environment';
import { LmsClient } from './contracts/lms-client';
import {
  LmsLoginCredentials,
  LmsUserRole,
  NormalizedLmsUser,
} from './contracts/lms-types';
import {
  InvalidLmsCredentialsError,
  LmsUnavailableError,
} from './eacc-lms.errors';
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
  admin: '/',
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
  ): Promise<NormalizedLmsUser> {
    const html = await this.loadAuthenticatedHtml(url, sessionCookie, timeout);

    if (role === 'student') {
      return parseLmsDashboardHtml(html, role);
    }

    if (role === 'teacher') {
      return parseTeacherDashboardHtml(html, role);
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
}

function tryParseJson(value: string): { value: unknown } | undefined {
  try {
    return { value: JSON.parse(value) as unknown };
  } catch {
    return undefined;
  }
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

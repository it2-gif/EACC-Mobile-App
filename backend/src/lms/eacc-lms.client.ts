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
  findAdminKeypersonId,
  parseAdminCourseEditHtml,
  parseAdminCourseIdsHtml,
  parseAdminCoursesHtml,
  parseAdminFromUserList,
  parseAdminSidebarName,
  parseAdminCourseStudentsHtml,
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

    const dashboardUrl = new URL(dashboardPaths[credentials.role], baseUrl);
    const jsonPayload = tryParseJson(responseText);
    if (jsonPayload !== undefined) {
      const user = parseLmsResponse(jsonPayload.value, credentials.role);

      if (credentials.role === 'teacher') {
        return {
          ...user,
          courses: await this.loadTeacherCoursesWithStudents(
            baseUrl,
            mergeSessionCookie(sessionCookie, response.headers),
            timeout,
            user.courses,
          ),
        };
      }

      if (credentials.role !== 'admin') {
        return user;
      }

      return this.loadAdminCoursesForUser(
        dashboardUrl,
        mergeSessionCookie(sessionCookie, response.headers),
        timeout,
        user,
        credentials,
      );
    }

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
        const coursesWithStudents = await this.loadTeacherCoursesWithStudents(
          baseUrl,
          mergeSessionCookie(sessionCookie, response.headers),
          timeout,
          courses,
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

  private async loadTeacherCoursesWithStudents(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    courses: NormalizedLmsCourse[],
  ): Promise<NormalizedLmsCourse[]> {
    return Promise.all(
      courses.map(async (course) => {
        const detailsHtml = await this.loadAuthenticatedHtml(
          new URL(
            `/teacher/lms_details.php?wcid=${encodeURIComponent(course.lmsCourseId)}`,
            baseUrl,
          ),
          sessionCookie,
          timeout,
        );

        return {
          ...course,
          students: parseTeacherCourseStudentsHtml(detailsHtml),
        };
      }),
    );
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

      return {
        ...admin,
        courses: await this.loadAdminCoursesForAccess(
          url.origin,
          sessionCookie,
          timeout,
          html,
          admin,
          credentials!,
        ),
      };
    }

    throw new LmsUnavailableError();
  }

  private async loadAdminCoursesForUser(
    dashboardUrl: URL,
    sessionCookie: string,
    timeout: number,
    admin: NormalizedLmsUser,
    credentials: LmsLoginCredentials,
  ): Promise<NormalizedLmsUser> {
    const dashboardHtml = await this.loadAuthenticatedHtml(
      dashboardUrl,
      sessionCookie,
      timeout,
    );

    return {
      ...admin,
      courses: await this.loadAdminCoursesForAccess(
        dashboardUrl.origin,
        sessionCookie,
        timeout,
        dashboardHtml,
        admin,
        credentials,
      ),
    };
  }

  private async loadAdminCoursesForAccess(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    dashboardHtml: string,
    admin: NormalizedLmsUser,
    credentials: LmsLoginCredentials,
  ): Promise<NormalizedLmsCourse[]> {
    if (admin.isSuperAdmin) {
      return this.loadAdminAllCoursesWithStudents(
        baseUrl,
        sessionCookie,
        timeout,
        dashboardHtml,
      );
    }

    return this.loadAdminKeyPersonCoursesWithStudents(
      baseUrl,
      sessionCookie,
      timeout,
      dashboardHtml,
      admin,
      credentials.username,
      credentials.hints?.knownCourseIds ?? [],
    );
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

  /**
   * Discovers the admin's keyperson courses then loads the enrolled student
   * list for each matched course — same as the teacher flow uses
   * /teacher/lms_details.php?wcid={id}.
   */
  private async loadAdminKeyPersonCoursesWithStudents(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    dashboardHtml: string,
    admin: NormalizedLmsUser,
    loginUsername: string,
    extraCandidateIds: string[] = [],
  ): Promise<NormalizedLmsCourse[]> {
    const courses = await this.loadAdminKeyPersonCourses(
      baseUrl,
      sessionCookie,
      timeout,
      dashboardHtml,
      admin,
      loginUsername,
      extraCandidateIds,
    );

    // Load students for every matched course in parallel.
    return Promise.all(
      courses.map(async (course) => {
        let detailsHtml: string | undefined;
        try {
          detailsHtml = await this.loadAuthenticatedHtml(
            new URL(
              `/view_students2.php?wcid=${encodeURIComponent(course.lmsCourseId)}`,
              baseUrl,
            ),
            sessionCookie,
            timeout,
          );
          return {
            ...course,
            students: parseAdminCourseStudentsHtml(detailsHtml),
          };
        } catch (error) {
          console.error(
            `[KeyPerson] Failed to load students for course ${course.lmsCourseId}:`,
            error,
          );
          if (detailsHtml) {
            try {
              require('fs').writeFileSync('lms_details_dump.html', detailsHtml);
              console.log(`[KeyPerson] Dumped HTML to lms_details_dump.html`);
            } catch (e) {}
          }
          // Student list unavailable for this course — return without students.
          return course;
        }
      }),
    );
  }

  private async loadAdminAllCoursesWithStudents(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    dashboardHtml: string,
  ): Promise<NormalizedLmsCourse[]> {
    const courseIds = uniqueStrings([
      ...parseAdminCoursesHtml(dashboardHtml, '', '').map(
        (course) => course.lmsCourseId,
      ),
      ...parseAdminCourseIdsHtml(dashboardHtml),
      ...(await this.loadAdminCourseIds(baseUrl, sessionCookie, timeout)),
    ]);
    const courses = await this.loadAdminCourseDetails(
      baseUrl,
      sessionCookie,
      timeout,
      courseIds,
    );

    return Promise.all(
      courses.map((course) =>
        this.loadAdminCourseStudents(baseUrl, sessionCookie, timeout, course),
      ),
    );
  }

  private async loadAdminCourseStudents(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    course: NormalizedLmsCourse,
  ): Promise<NormalizedLmsCourse> {
    try {
      const detailsHtml = await this.loadAuthenticatedHtml(
        new URL(
          `/view_students2.php?wcid=${encodeURIComponent(course.lmsCourseId)}`,
          baseUrl,
        ),
        sessionCookie,
        timeout,
      );

      return {
        ...course,
        students: parseAdminCourseStudentsHtml(detailsHtml),
      };
    } catch {
      return course;
    }
  }

  private async loadAdminCourseIds(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
  ): Promise<string[]> {
    try {
      const html = await this.loadAuthenticatedHtml(
        new URL('/courses.php', baseUrl),
        sessionCookie,
        timeout,
      );
      const courseIds = parseAdminCourseIdsHtml(html);
      console.log(
        `[AdminCourses] /courses.php -> ${courseIds.length} course IDs found`,
      );
      return courseIds;
    } catch (error) {
      console.log('[AdminCourses] /courses.php failed:', error);
      return [];
    }
  }

  private async loadAdminCourseDetails(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    courseIds: string[],
  ): Promise<NormalizedLmsCourse[]> {
    const BATCH = 6;
    const courses: NormalizedLmsCourse[] = [];

    for (let i = 0; i < courseIds.length; i += BATCH) {
      const batch = courseIds.slice(i, i + BATCH);
      const results = await Promise.allSettled(
        batch.map(async (courseId) => {
          const url = new URL('/edit_course.php', baseUrl);
          url.searchParams.set('wcid', courseId);
          const html = await this.loadAuthenticatedHtml(
            url,
            sessionCookie,
            timeout,
          );

          return (
            parseAdminCourseEditHtml(html, courseId) ?? {
              lmsCourseId: courseId,
              name: `Course ${courseId}`,
            }
          );
        }),
      );

      for (const result of results) {
        if (result.status === 'fulfilled') {
          courses.push(result.value);
        }
      }
    }

    return uniqueCourses(courses);
  }

  private async loadAdminKeyPersonCourses(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    dashboardHtml: string,
    admin: NormalizedLmsUser,
    loginUsername: string,
    extraCandidateIds: string[] = [],
  ): Promise<NormalizedLmsCourse[]> {
    // ── Step 1: Get all course IDs from /courses.php ──
    let allCourseIds: string[] = [];
    try {
      const html = await this.loadAuthenticatedHtml(
        new URL('/courses.php', baseUrl),
        sessionCookie,
        timeout,
      );
      allCourseIds = parseAdminCourseIdsHtml(html);
      console.log(
        `[KeyPerson] /courses.php → ${allCourseIds.length} course IDs found`,
      );
    } catch (err) {
      console.log(`[KeyPerson] /courses.php FAILED:`, err);
    }

    // ── Step 2: Discover admin's NUMERIC LMS ID ──
    // Strategy A (most reliable): fetch /hr/view_users.php and find the row
    // where username = loginUsername. Gives exact numeric ID + short name
    // directly from the admin table without any fuzzy matching.
    let adminNumericId: string | undefined = /^\d+$/.test(
      admin.lmsUserId.trim(),
    )
      ? admin.lmsUserId.trim()
      : undefined;
    let resolvedDisplayName = admin.name;

    if (!adminNumericId) {
      try {
        const hrHtml = await this.loadAuthenticatedHtml(
          new URL('/hr/view_users.php', baseUrl),
          sessionCookie,
          timeout,
        );
        const hrAdmin = parseAdminFromUserList(hrHtml, loginUsername);
        if (hrAdmin) {
          adminNumericId = hrAdmin.id;
          resolvedDisplayName = hrAdmin.shortName;
          console.log(
            `[KeyPerson] /hr/view_users.php → id="${adminNumericId}" shortName="${resolvedDisplayName}"`,
          );
        }
      } catch {
        // /hr/view_users.php not accessible for this admin role — use fallback.
      }
    }

    // Strategy B (fallback): scan the keyperson dropdown on a sample course
    // and fuzzy-match the admin's display name against option texts.
    if (!adminNumericId) {
      const sampleIds = (
        extraCandidateIds.length > 0 ? extraCandidateIds : allCourseIds
      ).slice(0, 5);

      console.log(
        `[KeyPerson] username="${loginUsername}" name="${resolvedDisplayName}" — trying ${sampleIds.length} sample courses...`,
      );

      for (const sampleId of sampleIds) {
        try {
          const url = new URL('/edit_course.php', baseUrl);
          url.searchParams.set('wcid', sampleId);
          const html = await this.loadAuthenticatedHtml(
            url,
            sessionCookie,
            timeout,
          );
          adminNumericId = findAdminKeypersonId(
            html,
            loginUsername,
            resolvedDisplayName,
          );
          console.log(
            `[KeyPerson] course ${sampleId} → discovered numericId="${adminNumericId}"`,
          );
          if (adminNumericId) break;
        } catch {
          // Try the next sample.
        }
      }
    }

    if (!adminNumericId) {
      console.log(
        `[KeyPerson] WARNING: could not discover numeric ID — will use fallback string matching`,
      );
    }

    // ── Step 3: Verify candidate courses against admin's identity ──
    const dashboardCourses = parseAdminCoursesHtml(
      dashboardHtml,
      admin.lmsUserId,
      admin.name,
    );
    const candidateIds = uniqueStrings([
      ...dashboardCourses.map((c) => c.lmsCourseId),
      ...parseAdminCourseIdsHtml(dashboardHtml),
      ...readConfiguredKeyPersonCourseIds(admin.lmsUserId),
      ...readConfiguredKeyPersonCourseIds(loginUsername.toLowerCase()),
      ...extraCandidateIds,
      ...(extraCandidateIds.length === 0 ? allCourseIds : []),
    ]);

    console.log(`[KeyPerson] ${candidateIds.length} candidates to verify`);

    if (candidateIds.length === 0) {
      console.log(`[KeyPerson] No candidates — returning empty`);
      return dashboardCourses;
    }

    // Verify in parallel batches of 6 to keep login time reasonable.
    const BATCH = 6;
    const verifiedCourses: NormalizedLmsCourse[] = [];

    for (let i = 0; i < candidateIds.length; i += BATCH) {
      const batch = candidateIds.slice(i, i + BATCH);
      const results = await Promise.allSettled(
        batch.map(async (courseId) => {
          const url = new URL('/edit_course.php', baseUrl);
          url.searchParams.set('wcid', courseId);
          const html = await this.loadAuthenticatedHtml(
            url,
            sessionCookie,
            timeout,
          );
          return { courseId, course: parseAdminCourseEditHtml(html, courseId) };
        }),
      );

      for (const result of results) {
        if (result.status !== 'fulfilled') continue;
        const { courseId, course } = result.value;
        const match = isAdminKeyPerson(
          course,
          admin,
          loginUsername,
          adminNumericId,
        );
        console.log(
          `[KeyPerson] course ${courseId}: keypersonId="${course?.keyPersonLmsUserId}" name="${course?.keyPersonName}" → match=${match}`,
        );
        if (match) {
          verifiedCourses.push({
            lmsCourseId: courseId,
            name: course?.name ?? `Course ${courseId}`,
            category: course?.category,
            keyPersonLmsUserId: admin.lmsUserId,
            keyPersonName: course?.keyPersonName ?? admin.name,
          });
        }
      }
    }

    console.log(
      `[KeyPerson] RESULT: ${verifiedCourses.length} courses matched for "${loginUsername}"`,
    );

    // If we successfully discovered the numeric ID the verification was reliable:
    // return only matched courses (even if empty). Do NOT fall back to
    // dashboardCourses — for a standard admin the dashboard lists ALL courses,
    // which would show every course in the LMS to a key-person admin.
    if (adminNumericId !== undefined) {
      return uniqueCourses(verifiedCourses);
    }

    // Numeric ID discovery failed entirely — fall back to dashboard courses as
    // a last resort (better than showing nothing for edge-case account types).
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

/**
 * Checks whether this course belongs to the given admin as key person.
 *
 * Primary check: compare the course's keyperson column value (a numeric LMS
 * admin ID, e.g. "76") against the admin's discovered numeric ID.
 * This is exact — if it matches, the course is theirs.
 *
 * Fallback (only when numeric ID could not be discovered): compare against
 * the login username or display name as a last resort.
 */
function isAdminKeyPerson(
  course: NormalizedLmsCourse | undefined,
  admin: NormalizedLmsUser,
  loginUsername: string,
  adminNumericId?: string,
): boolean {
  if (!course?.keyPersonLmsUserId) return false;

  const keyId = course.keyPersonLmsUserId.trim();

  // ── Primary: numeric ID match ──────────────────────────────────────────────
  // The LMS stores the admin's numeric ID in the keyperson column.
  // If we discovered it, use it exclusively — no guessing needed.
  if (adminNumericId) {
    return keyId === adminNumericId.trim();
  }

  // ── Fallback: string comparisons (numeric ID discovery failed) ─────────────
  const keyIdLower = keyId.toLowerCase();
  if (keyIdLower === admin.lmsUserId.toLowerCase().trim()) return true;
  if (keyIdLower === loginUsername.toLowerCase().trim()) return true;

  const keyName = (course.keyPersonName ?? '').toLowerCase().trim();
  const adminName = admin.name.toLowerCase().trim();
  if (keyName && adminName && keyName === adminName) return true;

  return false;
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

  // Try JS-variable patterns first (most specific).
  const jsDisplayName = readAdminIdentityValue(html, [
    'admin_shortname',
    'adminShortname',
    'short_name',
    'shortName',
    'shortname',
    'username',
    'admin_name',
    'ad_name',
  ]);

  // Fall back to the AdminLTE user-panel sidebar link text — this is the
  // admin's SHORT NAME (e.g. "developer") as shown in the LMS admin table,
  // which is exactly what appears in every course's keyperson dropdown.
  // Extracting it lets findAdminKeypersonId do an exact match.
  const sidebarName = parseAdminSidebarName(html);

  const displayName = jsDisplayName ?? sidebarName ?? trimmed;

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
      new RegExp(
        `\\b${escapedKey}\\b\\s*(?:=|:|=>)\\s*["']?([^"',}\\s<>]+)`,
        'i',
      ),
      new RegExp(`name=["']${escapedKey}["'][^>]*value=["']?([^"'>\\s]+)`, 'i'),
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

  const fullAccessKeys = ['full[_-]?access', 'fullaccess', 'fullaccese'];

  const directPatterns = fullAccessKeys.flatMap((key) => [
    new RegExp(`\\b${key}\\b\\s*(?:=|:|=>)\\s*["']?1["']?(?!\\d)`),
    new RegExp(`["']${key}["']\\s*:\\s*["']?1["']?(?!\\d)`),
    new RegExp(`${key}["'\\s:=]+1(?!\\d)`),
  ]);

  if (directPatterns.some((pattern) => pattern.test(normalized))) {
    return true;
  }

  const inputPattern =
    /<input[^>]+name\s*=\s*["']([^"']+)["'][^>]*value\s*=\s*["']?([^"'\s>]+)["']?[^>]*>/g;

  for (const match of normalized.matchAll(inputPattern)) {
    const key = match[1].replace(/[-_\s]/g, '');
    const value = match[2].trim();

    if (['fullaccess', 'fullaccese'].includes(key) && value === '1') {
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

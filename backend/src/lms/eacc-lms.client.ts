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
  parseAdminAccessFlagsHtml,
  parseAdminCourseEditHtml,
  parseAdminCourseIdsHtml,
  parseAdminCoursesHtml,
  parseAdminCourseTableSummary,
  parseAdminFromUserList,
  parseAdminSidebarName,
  parseAdminCourseStudentsHtml,
} from './eacc-lms.admin-courses-parser';
import { parseTeacherCourseStudentsHtml } from './eacc-lms.course-students-parser';
import { parseStudentCoursesHtml } from './eacc-lms.courses-parser';
import { parseLmsDashboardHtml } from './eacc-lms.html-parser';
import { parseTeacherDashboardHtml } from './eacc-lms.teacher-parser';
import { parseLmsPhpArrayResponse, parseLmsResponse } from './eacc-lms.parser';

const loginPaths: Record<LmsUserRole, string> = {
  student: '/members/login_1_app.php',
  teacher: '/teacher/login_1_app.php',
  admin: '/login_1_app.php',
};

const dashboardPaths: Record<LmsUserRole, string> = {
  student: '/members/',
  teacher: '/teacher/index.php',
  admin: '/front.php',
};

interface AdminCourseCatalog {
  courses: NormalizedLmsCourse[];
  isComplete: boolean;
  expectedCount?: number;
}

interface AdminCourseLoadResult {
  courses: NormalizedLmsCourse[];
  isCourseCatalogComplete?: boolean;
}

const lmsBrowserHeaders = {
  'user-agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36',
  'accept-language': 'en-US,en;q=0.9',
  'cache-control': 'no-cache',
};

@Injectable()
export class EaccLmsClient implements LmsClient {
  constructor(private readonly config: ConfigService<Environment, true>) {}

  async loadAdminCourseById(
    credentials: Pick<LmsLoginCredentials, 'username' | 'password'>,
    lmsCourseId: string,
  ): Promise<NormalizedLmsCourse | undefined> {
    const courseId = lmsCourseId.trim();
    if (!courseId) return undefined;

    const baseUrl = this.config.get('LMS_BASE_URL', { infer: true });
    const timeout = this.config.get('LMS_REQUEST_TIMEOUT_MS', { infer: true });
    const sessionCookie = await this.loginAdminSession(
      baseUrl,
      timeout,
      credentials,
    );
    const editUrl = new URL('/edit_course.php', baseUrl);
    editUrl.searchParams.set('wcid', courseId);
    const detailsHtml = await this.loadAuthenticatedHtml(
      editUrl,
      sessionCookie,
      timeout,
    );
    const course = parseAdminCourseEditHtml(detailsHtml, courseId);

    if (!course) return undefined;

    const catalogResult = await this.loadAdminCourseCatalog(
      baseUrl,
      sessionCookie,
      timeout,
    );
    const catalog = catalogResult.courses;
    const catalogCourse = catalog.find(
      (entry) => entry.lmsCourseId === course.lmsCourseId,
    );
    const [courseWithTeacherName] = await this.resolveCourseTeacherNames(
      baseUrl,
      sessionCookie,
      timeout,
      [mergeCourseCatalogData(course, catalogCourse)],
    );

    return this.loadAdminCourseStudents(
      baseUrl,
      sessionCookie,
      timeout,
      courseWithTeacherName,
    );
  }

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

    response = await this.fetchLms(
      endpoint,
      {
        method: 'POST',
        headers: {
          accept: 'text/html,application/json',
          'content-type': 'application/x-www-form-urlencoded',
          ...(sessionCookie ? { cookie: sessionCookie } : {}),
        },
        body,
        redirect: 'follow',
      },
      timeout,
      `login ${credentials.role}`,
    );

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
      console.warn(
        `[LMS] login ${credentials.role} returned ${response.status} ${response.statusText}`,
      );
      throw new LmsUnavailableError();
    }

    const dashboardUrl = new URL(dashboardPaths[credentials.role], baseUrl);
    let parsedUser = parseStructuredLmsResponse(responseText, credentials.role);
    let parsedResponseHeaders = response.headers;

    if (parsedUser === undefined && credentials.role === 'admin') {
      const rawResponse = await this.fetchLms(
        endpoint,
        {
          method: 'POST',
          headers: {
            accept: 'text/html,application/json',
            'content-type': 'application/x-www-form-urlencoded',
            ...(sessionCookie ? { cookie: sessionCookie } : {}),
          },
          body: new URLSearchParams({
            ty: credentials.role,
            username: credentials.username,
            inputPassword: credentials.password,
          }),
          redirect: 'manual',
        },
        timeout,
        'login admin raw response',
      );
      const rawResponseText = await rawResponse.text();

      if (
        rawResponse.url.includes('login=failed') ||
        rawResponse.status === 401 ||
        rawResponse.status === 403 ||
        rawResponseText.includes('Username Not Found')
      ) {
        throw new InvalidLmsCredentialsError();
      }

      const rawParsedUser = parseStructuredLmsResponse(
        rawResponseText,
        credentials.role,
      );
      if (rawParsedUser !== undefined) {
        parsedUser = rawParsedUser;
        parsedResponseHeaders = rawResponse.headers;
      } else {
        console.warn(
          `[AdminLoginResponse] user="${credentials.username}" could not parse app response; status=${response.status}; url=${response.url}; preview="${previewLmsResponse(responseText)}"`,
        );
      }
    }

    if (parsedUser !== undefined) {
      const user = { ...parsedUser };

      if (credentials.role === 'admin') {
        console.log(
          `[AdminLoginResponse] user="${credentials.username}" fullAccess=${
            user.isSuperAdmin === true ? 1 : 0
          } managerOperation=${
            user.isManagerOperation === true ? 1 : 0
          } technicalSupport=${user.isTechnicalSupport === true ? 1 : 0} academic=${user.isAcademic === true ? 1 : 0}`,
        );
      }

      if (credentials.role === 'teacher') {
        return {
          ...user,
          courses: await this.loadTeacherCoursesWithStudents(
            baseUrl,
            mergeSessionCookie(sessionCookie, parsedResponseHeaders),
            timeout,
            user.courses.map((course) => ({
              ...course,
              teacherName: course.teacherName ?? user.name,
              teacherLmsUserId: course.teacherLmsUserId ?? user.lmsUserId,
            })),
          ),
        };
      }

      if (credentials.role !== 'admin') {
        return user;
      }

      return this.loadAdminCoursesForUser(
        dashboardUrl,
        mergeSessionCookie(sessionCookie, parsedResponseHeaders),
        timeout,
        user,
        credentials,
      );
    }

    const user = await this.loadDashboard(
      dashboardUrl,
      mergeSessionCookie(sessionCookie, parsedResponseHeaders),
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
        mergeSessionCookie(sessionCookie, parsedResponseHeaders),
        timeout,
      );

      const courses = await this.enrichCoursesWithAdminCatalog(
        baseUrl,
        timeout,
        parseStudentCoursesHtml(coursesHtml),
      );

      if (credentials.role === 'teacher') {
        const coursesWithStudents = await this.loadTeacherCoursesWithStudents(
          baseUrl,
          mergeSessionCookie(sessionCookie, parsedResponseHeaders),
          timeout,
          courses.map((course) => ({
            ...course,
            teacherName: course.teacherName ?? user.name,
            teacherLmsUserId: course.teacherLmsUserId ?? user.lmsUserId,
          })),
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

  private async loginAdminSession(
    baseUrl: string,
    timeout: number,
    credentials: Pick<LmsLoginCredentials, 'username' | 'password'>,
  ): Promise<string> {
    const endpoint = new URL(loginPaths.admin, baseUrl);
    const sessionCookie = await this.createSession(baseUrl, timeout);
    const body = new URLSearchParams({
      ty: 'admin',
      username: credentials.username,
      inputPassword: credentials.password,
    });

    let response: Response;

    response = await this.fetchLms(
      endpoint,
      {
        method: 'POST',
        headers: {
          accept: 'text/html,application/json',
          'content-type': 'application/x-www-form-urlencoded',
          ...(sessionCookie ? { cookie: sessionCookie } : {}),
        },
        body,
        redirect: 'follow',
      },
      timeout,
      'admin session login',
    );

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
      console.warn(
        `[LMS] admin session login returned ${response.status} ${response.statusText}`,
      );
      throw new LmsUnavailableError();
    }

    return mergeSessionCookie(sessionCookie, response.headers);
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

  private async enrichCoursesWithAdminCatalog(
    baseUrl: string,
    timeout: number,
    courses: NormalizedLmsCourse[],
  ): Promise<NormalizedLmsCourse[]> {
    if (courses.length === 0) return courses;

    const catalog = await this.loadAdminCourseCatalogWithSyncCredentials(
      baseUrl,
      timeout,
    );
    if (catalog.length === 0) return courses;

    const catalogById = new Map(
      catalog.map((course) => [course.lmsCourseId, course]),
    );

    return courses.map((course) =>
      mergeCourseCatalogData(course, catalogById.get(course.lmsCourseId)),
    );
  }

  private async loadAdminCourseCatalogWithSyncCredentials(
    baseUrl: string,
    timeout: number,
  ): Promise<NormalizedLmsCourse[]> {
    const username = this.config.get('LMS_SYNC_ADMIN_USERNAME', {
      infer: true,
    });
    const password = this.config.get('LMS_SYNC_ADMIN_PASSWORD', {
      infer: true,
    });

    if (!username || !password) return [];

    try {
      const sessionCookie = await this.loginAdminSession(baseUrl, timeout, {
        username,
        password,
      });

      return (
        await this.loadAdminCourseCatalog(baseUrl, sessionCookie, timeout)
      ).courses;
    } catch (error) {
      console.log('[AdminCourses] sync catalog login failed:', error);
      return [];
    }
  }

  private async createSession(
    baseUrl: string,
    timeout: number,
  ): Promise<string> {
    let response: Response;

    response = await this.fetchLms(
      new URL('/login.php', baseUrl),
      {
        headers: { accept: 'text/html' },
      },
      timeout,
      'create session',
    );

    if (!response.ok) {
      console.warn(
        `[LMS] create session returned ${response.status} ${response.statusText}`,
      );
      throw new LmsUnavailableError();
    }

    return extractSessionCookie(response.headers) ?? '';
  }

  private async fetchLms(
    url: URL,
    init: RequestInit,
    timeout: number,
    action: string,
  ): Promise<Response> {
    const attempts = 2;

    for (let attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        return await fetch(url, {
          ...init,
          headers: {
            ...lmsBrowserHeaders,
            ...(init.headers as Record<string, string> | undefined),
          },
          signal: AbortSignal.timeout(timeout),
        });
      } catch (error) {
        console.warn(
          `[LMS] ${action} request failed on attempt ${attempt}/${attempts}: ${formatLmsFetchError(
            error,
          )}`,
        );

        if (attempt < attempts) {
          await sleep(350);
        }
      }
    }

    throw new LmsUnavailableError();
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
      const parsedAdmin = {
        ...parseAdminIdentity(
          credentials!.username,
          `${loginResponseHtml}
${html}`,
        ),
      };
      const admin = await this.resolveAdminIdentity(
        url.origin,
        sessionCookie,
        timeout,
        parsedAdmin,
        credentials!.username,
      );
      const courseLoad = await this.loadAdminCoursesForAccess(
        url.origin,
        sessionCookie,
        timeout,
        html,
        admin,
        credentials!,
      );

      return {
        ...admin,
        courses: courseLoad.courses,
        isCourseCatalogComplete: courseLoad.isCourseCatalogComplete,
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
    const verifiedAdmin = await this.resolveAdminIdentity(
      dashboardUrl.origin,
      sessionCookie,
      timeout,
      admin,
      credentials.username,
    );
    const courseLoad = await this.loadAdminCoursesForAccess(
      dashboardUrl.origin,
      sessionCookie,
      timeout,
      dashboardHtml,
      verifiedAdmin,
      credentials,
    );

    return {
      ...verifiedAdmin,
      courses: courseLoad.courses,
      isCourseCatalogComplete: courseLoad.isCourseCatalogComplete,
    };
  }

  private async resolveAdminIdentity(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    admin: NormalizedLmsUser,
    loginUsername: string,
  ): Promise<NormalizedLmsUser> {
    try {
      const usersHtml = await this.loadAuthenticatedHtml(
        new URL('/hr/view_users.php', baseUrl),
        sessionCookie,
        timeout,
      );
      const matchedAdmin = parseAdminFromUserList(usersHtml, loginUsername);
      if (!matchedAdmin) return admin;
      const detailsAccess = matchedAdmin.detailsPath
        ? await this.loadAdminDetailsAccessFlags(
            baseUrl,
            sessionCookie,
            timeout,
            matchedAdmin.detailsPath,
          )
        : undefined;
      const overrides = readAdminAccessOverrides(
        matchedAdmin.id,
        this.config.get('LMS_ADMIN_ACCESS_OVERRIDES', { infer: true }),
      );
      const isSuperAdmin =
        matchedAdmin.isSuperAdmin === true ||
        detailsAccess?.isSuperAdmin === true ||
        admin.isSuperAdmin === true ||
        overrides.isSuperAdmin === true;
      const isManagerOperation =
        matchedAdmin.isManagerOperation === true ||
        detailsAccess?.isManagerOperation === true ||
        admin.isManagerOperation === true ||
        overrides.isManagerOperation === true;
      const isTechnicalSupport =
        matchedAdmin.isTechnicalSupport === true ||
        detailsAccess?.isTechnicalSupport === true ||
        admin.isTechnicalSupport === true ||
        overrides.isTechnicalSupport === true;
      const isAcademic =
        matchedAdmin.isAcademic === true ||
        detailsAccess?.isAcademic === true ||
        admin.isAcademic === true ||
        overrides.isAcademic === true;

      console.log(
        `[AdminAccess] user="${loginUsername}" id="${matchedAdmin.id}" fullAccess=${
          isSuperAdmin ? 1 : 0
        } managerOperation=${isManagerOperation ? 1 : 0} technicalSupport=${
          isTechnicalSupport ? 1 : 0
        } academic=${isAcademic ? 1 : 0}`,
      );

      return {
        ...admin,
        lmsUserId: matchedAdmin.id,
        name: matchedAdmin.shortName,
        isSuperAdmin,
        isManagerOperation,
        isTechnicalSupport,
        isAcademic,
      };
    } catch {
      return admin;
    }
  }

  private async loadAdminDetailsAccessFlags(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    detailsPath: string,
  ) {
    try {
      const detailsHtml = await this.loadAuthenticatedHtml(
        new URL(detailsPath, baseUrl),
        sessionCookie,
        timeout,
      );

      return parseAdminAccessFlagsHtml(detailsHtml);
    } catch {
      return undefined;
    }
  }

  private async loadAdminCoursesForAccess(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    dashboardHtml: string,
    admin: NormalizedLmsUser,
    credentials: LmsLoginCredentials,
  ): Promise<AdminCourseLoadResult> {
    if (
      admin.isSuperAdmin ||
      admin.isManagerOperation ||
      admin.isAcademic ||
      credentials.hints?.canViewAllCourses === true
    ) {
      return this.loadAdminAllCoursesWithStudents(
        baseUrl,
        sessionCookie,
        timeout,
        dashboardHtml,
      );
    }

    return {
      courses: await this.loadAdminKeyPersonCoursesWithStudents(
        baseUrl,
        sessionCookie,
        timeout,
        dashboardHtml,
        admin,
        credentials.username,
        credentials.hints?.knownCourseIds ?? [],
      ),
      isCourseCatalogComplete: true,
    };
  }

  private async loadAuthenticatedHtml(
    url: URL,
    sessionCookie: string,
    timeout: number,
  ): Promise<string> {
    let response: Response;

    response = await this.fetchLms(
      url,
      {
        headers: {
          accept: 'text/html',
          ...(sessionCookie ? { cookie: sessionCookie } : {}),
        },
        redirect: 'follow',
      },
      timeout,
      `load ${url.pathname}`,
    );

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
    const coursesWithTeacherNames = await this.resolveCourseTeacherNames(
      baseUrl,
      sessionCookie,
      timeout,
      courses,
    );

    // Load students for every matched course in parallel.
    return Promise.all(
      coursesWithTeacherNames.map(async (course) => {
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
  ): Promise<AdminCourseLoadResult> {
    const catalogResult = await this.loadAdminCourseCatalog(
      baseUrl,
      sessionCookie,
      timeout,
    );
    const catalog = catalogResult.courses;
    const courseIds = uniqueStrings([
      ...parseAdminCoursesHtml(dashboardHtml, '', '').map(
        (course) => course.lmsCourseId,
      ),
      ...parseAdminCourseIdsHtml(dashboardHtml),
      ...catalog.map((course) => course.lmsCourseId),
      ...(catalog.length === 0
        ? await this.loadAdminCourseIds(baseUrl, sessionCookie, timeout)
        : []),
    ]);
    const courses = await this.loadAdminCourseDetails(
      baseUrl,
      sessionCookie,
      timeout,
      courseIds,
    );
    const catalogById = new Map(
      catalog.map((course) => [course.lmsCourseId, course]),
    );
    const coursesWithCatalogNames = courses.map((course) =>
      mergeCourseCatalogData(course, catalogById.get(course.lmsCourseId)),
    );
    const coursesWithTeacherNames = await this.resolveCourseTeacherNames(
      baseUrl,
      sessionCookie,
      timeout,
      coursesWithCatalogNames,
    );

    // Full-access admins can see many courses. Loading every roster during
    // login causes repeated LMS timeouts, so roster details are loaded later
    // by the course detail/refresh endpoints when a specific course is opened.
    return {
      courses: coursesWithTeacherNames,
      isCourseCatalogComplete: catalogResult.isComplete,
    };
  }

  private async loadAdminCourseCatalog(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
  ): Promise<AdminCourseCatalog> {
    try {
      const html = await this.loadAuthenticatedHtml(
        new URL('/courses.php', baseUrl),
        sessionCookie,
        timeout,
      );
      const courses = parseAdminCoursesHtml(html, '', '');
      const summary = parseAdminCourseTableSummary(html);
      const completeness = summary.isComplete
        ? 'complete'
        : `incomplete ${summary.visibleRowCount}/${summary.totalCount ?? 'unknown'}`;
      console.log(
        `[AdminCourses] /courses.php -> ${courses.length} course records found (${completeness})`,
      );
      return {
        courses,
        isComplete: summary.isComplete,
        expectedCount: summary.totalCount,
      };
    } catch (error) {
      console.log('[AdminCourses] /courses.php catalog failed:', error);
      return { courses: [], isComplete: false };
    }
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

  private async resolveCourseTeacherNames(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    courses: NormalizedLmsCourse[],
  ): Promise<NormalizedLmsCourse[]> {
    const teacherNameCache = new Map<string, string | undefined>();

    return Promise.all(
      courses.map(async (course) => {
        if (
          isResolvedTeacherName(course.teacherName, course.teacherLmsUserId)
        ) {
          return course;
        }

        const teacherId = course.teacherLmsUserId?.trim();
        if (!teacherId) return course;

        if (!teacherNameCache.has(teacherId)) {
          teacherNameCache.set(
            teacherId,
            await this.loadTeacherNameById(
              baseUrl,
              sessionCookie,
              timeout,
              teacherId,
            ),
          );
        }

        const teacherName = teacherNameCache.get(teacherId);
        return teacherName ? { ...course, teacherName } : course;
      }),
    );
  }

  private async loadTeacherNameById(
    baseUrl: string,
    sessionCookie: string,
    timeout: number,
    teacherId: string,
  ): Promise<string | undefined> {
    try {
      const url = new URL('/teacher/get_teacher_name.php', baseUrl);
      url.searchParams.set('t_id', teacherId);
      const responseText = await this.loadAuthenticatedHtml(
        url,
        sessionCookie,
        timeout,
      );

      return parseTeacherNameResponse(responseText);
    } catch {
      return undefined;
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
    let courseCatalog: NormalizedLmsCourse[] = [];
    let allCourseIds: string[] = [];
    try {
      const html = await this.loadAuthenticatedHtml(
        new URL('/courses.php', baseUrl),
        sessionCookie,
        timeout,
      );
      courseCatalog = parseAdminCoursesHtml(html, '', '');
      allCourseIds = uniqueStrings([
        ...courseCatalog.map((course) => course.lmsCourseId),
        ...parseAdminCourseIdsHtml(html),
      ]);
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
    const catalogById = new Map(
      courseCatalog.map((course) => [course.lmsCourseId, course]),
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
          verifiedCourses.push(
            mergeCourseCatalogData(
              {
                lmsCourseId: courseId,
                name: course?.name ?? `Course ${courseId}`,
                category: course?.category,
                teacherLmsUserId: course?.teacherLmsUserId,
                teacherName: course?.teacherName,
                keyPersonLmsUserId: admin.lmsUserId,
                keyPersonName: course?.keyPersonName ?? admin.name,
              },
              catalogById.get(courseId),
            ),
          );
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

function mergeCourseCatalogData(
  course: NormalizedLmsCourse,
  catalogCourse: NormalizedLmsCourse | undefined,
): NormalizedLmsCourse {
  if (!catalogCourse) return course;

  const currentName = course.name.trim();
  const catalogName = catalogCourse.name.trim();
  const catalogCategory = catalogCourse.category?.trim();
  const shouldUseCatalogName =
    catalogName.length > 0 &&
    (isGenericCourseName(currentName, course.lmsCourseId) ||
      Boolean(
        catalogCategory &&
        currentName.toLowerCase() === catalogCategory.toLowerCase() &&
        catalogName.toLowerCase() !== currentName.toLowerCase(),
      ));

  return {
    ...course,
    name: shouldUseCatalogName ? catalogName : course.name,
    category: catalogCourse.category ?? course.category,
    teacherLmsUserId: course.teacherLmsUserId ?? catalogCourse.teacherLmsUserId,
    teacherName: course.teacherName ?? catalogCourse.teacherName,
  };
}

function isResolvedTeacherName(
  teacherName: string | undefined,
  teacherLmsUserId: string | undefined,
): boolean {
  const trimmed = teacherName?.trim();
  if (!trimmed) return false;
  if (teacherLmsUserId && trimmed === teacherLmsUserId.trim()) return false;
  return !/^\d+$/.test(trimmed);
}

function parseTeacherNameResponse(responseText: string): string | undefined {
  const trimmed = responseText.trim();
  if (!trimmed) return undefined;

  const json = tryParseJson(trimmed);
  if (json !== undefined) {
    return readTeacherNameFromUnknown(json.value);
  }

  const fieldMatch =
    /\[(?:teacher_name|teacherName|teacher_shortname|shortname|te_name|name)\]\s*=>\s*([^\r\n]+)/i.exec(
      trimmed,
    );
  if (fieldMatch?.[1]) {
    return cleanTeacherName(fieldMatch[1]);
  }

  const assignmentMatch =
    /(?:teacher_name|teacherName|teacher_shortname|shortname|te_name|name)\s*(?:=|:|=>)\s*["']?([^"',}\r\n<]+)/i.exec(
      trimmed,
    );
  if (assignmentMatch?.[1]) {
    return cleanTeacherName(assignmentMatch[1]);
  }

  const text = trimmed
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return cleanTeacherName(text);
}

function readTeacherNameFromUnknown(value: unknown): string | undefined {
  if (typeof value === 'string') return cleanTeacherName(value);
  if (typeof value !== 'object' || value === null) return undefined;

  if (Array.isArray(value)) {
    for (const entry of value) {
      const name = readTeacherNameFromUnknown(entry);
      if (name) return name;
    }
    return undefined;
  }

  const record = value as Record<string, unknown>;
  const keys = [
    'teacher_name',
    'teacherName',
    'teacher_shortname',
    'teacherShortname',
    'shortname',
    'te_name',
    'name',
  ];

  for (const key of keys) {
    const match = Object.keys(record).find(
      (candidate) => candidate.toLowerCase() === key.toLowerCase(),
    );
    const value = match ? record[match] : undefined;
    if (typeof value === 'string' || typeof value === 'number') {
      const name = cleanTeacherName(String(value));
      if (name) return name;
    }
  }

  return undefined;
}

function cleanTeacherName(value: string): string | undefined {
  const name = value.replace(/^["'\s]+|["'\s]+$/g, '').trim();
  if (!name || /^\d+$/.test(name) || /^array\s*\(/i.test(name)) {
    return undefined;
  }

  return name;
}

function isGenericCourseName(name: string, lmsCourseId: string): boolean {
  return (
    name.length === 0 ||
    name.toLowerCase() === `course ${lmsCourseId}`.toLowerCase()
  );
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

function previewLmsResponse(value: string): string {
  return value.replace(/\s+/g, ' ').trim().slice(0, 220);
}

function readAdminAccessOverrides(
  adminLmsUserId: string,
  configuredOverrides?: string,
): {
  isSuperAdmin?: boolean;
  isManagerOperation?: boolean;
  isTechnicalSupport?: boolean;
  isAcademic?: boolean;
} {
  const overrides = new Map<string, string[]>();

  for (const entry of (configuredOverrides ?? '').split(',')) {
    const [rawId, rawFlags] = entry.split(':');
    const id = rawId?.trim();
    const flags = rawFlags
      ?.split('|')
      .map((flag) => flag.trim().toLowerCase())
      .filter(Boolean);
    if (id && flags && flags.length > 0) {
      overrides.set(id, flags);
    }
  }

  const flags = overrides.get(adminLmsUserId.trim()) ?? [];

  return {
    isSuperAdmin:
      flags.includes('full_access') || flags.includes('super_admin'),
    isManagerOperation:
      flags.includes('manager_operation') || flags.includes('m_operation'),
    isTechnicalSupport:
      flags.includes('technical_support') || flags.includes('tec'),
    isAcademic:
      flags.includes('academic') ||
      flags.includes('teacher_manager') ||
      flags.includes('manage_teachers') ||
      flags.includes('manage_techers'),
  };
}

function parseStructuredLmsResponse(
  responseText: string,
  role: LmsUserRole,
): NormalizedLmsUser | undefined {
  const jsonPayload = tryParseJson(responseText);
  if (jsonPayload !== undefined) {
    return parseLmsResponse(jsonPayload.value, role);
  }

  return parseLmsPhpArrayResponse(responseText, role);
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
    isManagerOperation: hasAdminManagerOperation(html),
    isTechnicalSupport: hasAdminTechnicalSupport(html),
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
      new RegExp(`\\[\\s*${escapedKey}\\s*\\]\\s*=>\\s*([^\\r\\n\\[]+)`, 'i'),
      new RegExp(
        `\\b${escapedKey}\\b\\s*(?:=|:|=>)\\s*["']?([^"',}\\s<>]+)`,
        'i',
      ),
      new RegExp(`name=["']${escapedKey}["'][^>]*value=["']?([^"'>\\s]+)`, 'i'),
    ];

    for (const pattern of patterns) {
      const value = pattern
        .exec(html)?.[1]
        ?.trim()
        .replace(/^["']|["']$/g, '')
        .replace(/\)+$/g, '')
        .trim();
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
  return hasAdminBooleanFlag(html, ['fullaccess', 'fullaccese']);
}

function hasAdminManagerOperation(html: string): boolean {
  return hasAdminBooleanFlag(html, [
    'moperation',
    'mop',
    'operationmanager',
    'manageroperation',
    'managerop',
  ]);
}

function hasAdminTechnicalSupport(html: string): boolean {
  return hasAdminBooleanFlag(html, ['tec', 'tech', 'technicalsupport']);
}

function hasAdminAcademic(html: string): boolean {
  return hasAdminBooleanFlag(html, [
    'managetechers',
    'manageteachers',
    'manageteacher',
    'academic',
    'isacademic',
    'teachermanager',
  ]);
}

function hasAdminBooleanFlag(html: string, compactKeys: string[]): boolean {
  const normalized = html.toLowerCase();

  const fieldPatterns = compactKeys.map((key) => {
    if (key === 'fullaccess') return 'full[_\\s-]?access';
    if (key === 'moperation') return 'm[_\\s-]?operation';
    if (key === 'mop') return 'm[_\\s-]?op';
    if (key === 'operationmanager') return 'operation[_\\s-]?manager';
    if (key === 'manageroperation') return 'manager[_\\s-]?operation';
    if (key === 'managerop') return 'manager[_\\s-]?op';
    return key;
  });

  const directPatterns = fieldPatterns.flatMap((key) => [
    new RegExp(`\\b${key}\\b\\s*(?:=|:|=>)\\s*["']?1["']?(?!\\d)`),
    new RegExp(`["']${key}["']\\s*:\\s*["']?1["']?(?!\\d)`),
    new RegExp(`${key}["'\\s:=]+1(?!\\d)`),
    new RegExp(
      `(?:\\[\\s*)?["']?${key}["']?\\s*\\]?\\s*(?:=|:|=>)\\s*["']?1["']?(?!\\d)`,
    ),
  ]);

  if (directPatterns.some((pattern) => pattern.test(normalized))) {
    return true;
  }

  const inputPattern =
    /<input[^>]+name\s*=\s*["']([^"']+)["'][^>]*value\s*=\s*["']?([^"'\s>]+)["']?[^>]*>/g;

  for (const match of normalized.matchAll(inputPattern)) {
    const key = match[1].replace(/[-_\s]/g, '');
    const value = match[2].trim();

    if (compactKeys.includes(key) && value === '1') {
      return true;
    }
  }

  const reversedInputPattern =
    /<input[^>]+value\s*=\s*["']?([^"'\s>]+)["']?[^>]*name\s*=\s*["']([^"']+)["'][^>]*>/g;

  for (const match of normalized.matchAll(reversedInputPattern)) {
    const value = match[1].trim();
    const key = match[2].replace(/[-_\s]/g, '');

    if (compactKeys.includes(key) && value === '1') {
      return true;
    }
  }

  const selectFieldPattern = fieldPatterns.join('|');
  const selectPattern = new RegExp(
    `<select[^>]+name\\s*=\\s*["'](?:${selectFieldPattern})["'][^>]*>[\\s\\S]*?<option[^>]+value\\s*=\\s*["']?1["']?[^>]*selected[^>]*>`,
  );

  return selectPattern.test(normalized);
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

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function formatLmsFetchError(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }

  return String(error);
}

function looksLikeLoginPage(html: string): boolean {
  const normalized = html.toLowerCase();

  return (
    normalized.includes('name="inputpassword"') ||
    normalized.includes('username not found') ||
    normalized.includes('wrap-login100')
  );
}

import { InvalidLmsResponseError } from './eacc-lms.errors';
import {
  LmsUserRole,
  NormalizedLmsCourse,
  NormalizedLmsUser,
} from './contracts/lms-types';

type JsonObject = Record<string, unknown>;

const userFields: Record<
  LmsUserRole,
  { id: string[]; name: string[]; email: string[] }
> = {
  student: {
    id: ['st_id', 'student_id', 'id'],
    name: ['st_name', 'student_name', 'name'],
    email: ['st_email', 'student_email', 'email'],
  },
  teacher: {
    id: ['te_id', 'teacher_id', 'id'],
    name: ['te_name', 'teacher_name', 'name'],
    email: ['te_email', 'teacher_email', 'email'],
  },
  admin: {
    id: ['admin_id', 'ad_id', 'adminId', 'user_id', 'userId', 'id'],
    name: [
      'admin_shortname',
      'adminShortname',
      'short_name',
      'shortName',
      'shortname',
      'admin_name',
      'ad_name',
      'name',
      'username',
    ],
    email: ['admin_email', 'ad_email', 'email'],
  },
};

export function parseLmsResponse(
  payload: unknown,
  expectedRole: LmsUserRole,
): NormalizedLmsUser {
  const root = asObject(payload);
  const data = readRoleData(root, expectedRole);
  const fields = userFields[expectedRole];

  const lmsUserId = readRequiredString(data, fields.id);
  const name = readRequiredString(data, fields.name);
  const email = readOptionalString(data, fields.email);
  const responseRole = readOptionalString(data, ['role', 'type', 'user_type']);
  const isSuperAdmin =
    expectedRole === 'admin'
      ? hasAdminFullAccess(data) || hasAdminFullAccess(root)
      : false;

  if (responseRole && normalizeRole(responseRole) !== expectedRole) {
    throw new InvalidLmsResponseError();
  }

  return {
    lmsUserId,
    role: expectedRole,
    name,
    email,
    isSuperAdmin,
    courses: readCourses(
      data.courses ?? root.courses,
      root.admin ?? data.admin,
    ),
  };
}

function readRoleData(root: JsonObject, expectedRole: LmsUserRole): JsonObject {
  const rolePayload =
    expectedRole === 'admin' ? root.admin_name : root[expectedRole];

  if (Array.isArray(rolePayload) && rolePayload.length > 0) {
    return asObject(rolePayload[0]);
  }

  return asObject(root.data ?? root.user ?? root);
}

function readCourses(
  value: unknown,
  adminValues?: unknown,
): NormalizedLmsCourse[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new InvalidLmsResponseError();

  const admins = Array.isArray(adminValues) ? adminValues : [];

  return value.map((course, index) => {
    const data = asObject(course);
    const admin = admins[index] ? asObject(admins[index]) : {};

    return {
      lmsCourseId: readRequiredString(data, ['course_id', 'id']),
      name: readRequiredString(data, ['course_name', 'name']),
      category: readOptionalString(data, ['category', 'course_category']),
      keyPersonLmsUserId: readOptionalString(data, [
        'key_person',
        'key_person_id',
        'keyperson',
        'keyperson_id',
        'keyPerson',
        'keyPersonId',
        'keyPersonLmsUserId',
        'manager_id',
        'admin_id',
      ]),
      keyPersonName:
        readOptionalString(data, [
          'shortname',
          'Admin_shortname',
          'key_person_name',
          'keyperson_name',
          'keyPersonName',
          'manager_name',
          'admin_name',
        ]) ?? readOptionalString(admin, ['Admin_shortname', 'shortname']),
    };
  });
}

function hasAdminFullAccess(data: JsonObject): boolean {
  const accessLevel = readOptionalNumber(data, [
    'fullaccese',
    'full_access',
    'fullAccess',
  ]);

  return accessLevel === 1;
}

function asObject(value: unknown): JsonObject {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new InvalidLmsResponseError();
  }

  return value as JsonObject;
}

function readRequiredString(data: JsonObject, keys: string[]): string {
  const value = readOptionalString(data, keys);
  if (!value) throw new InvalidLmsResponseError();
  return value;
}

function readOptionalString(
  data: JsonObject,
  keys: string[],
): string | undefined {
  for (const key of keys) {
    const value = readValue(data, key);

    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }

    if (typeof value === 'number' && Number.isFinite(value)) {
      return String(value);
    }
  }

  return undefined;
}

function readOptionalNumber(
  data: JsonObject,
  keys: string[],
): number | undefined {
  for (const key of keys) {
    const value = readValue(data, key);

    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }

    if (typeof value === 'string' && value.trim().length > 0) {
      const parsed = Number(value.trim());
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }

  return undefined;
}

function readValue(data: JsonObject, key: string): unknown {
  if (Object.prototype.hasOwnProperty.call(data, key)) {
    return data[key];
  }

  const normalizedKey = key.toLowerCase();
  const matchingKey = Object.keys(data).find(
    (candidate) => candidate.toLowerCase() === normalizedKey,
  );

  return matchingKey === undefined ? undefined : data[matchingKey];
}

function normalizeRole(value: string): LmsUserRole | undefined {
  const role = value.trim().toLowerCase();

  if (role === 'student' || role === 'teacher' || role === 'admin') {
    return role;
  }

  return undefined;
}

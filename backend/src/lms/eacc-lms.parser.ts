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
    id: ['admin_id', 'ad_id', 'id'],
    name: ['admin_name', 'ad_name', 'name', 'username'],
    email: ['admin_email', 'ad_email', 'email'],
  },
};

export function parseLmsResponse(
  payload: unknown,
  expectedRole: LmsUserRole,
): NormalizedLmsUser {
  const root = asObject(payload);
  const data = asObject(root.data ?? root.user ?? root);
  const fields = userFields[expectedRole];

  const lmsUserId = readRequiredString(data, fields.id);
  const name = readRequiredString(data, fields.name);
  const email = readOptionalString(data, fields.email);
  const responseRole = readOptionalString(data, ['role', 'type', 'user_type']);

  if (responseRole && normalizeRole(responseRole) !== expectedRole) {
    throw new InvalidLmsResponseError();
  }

  return {
    lmsUserId,
    role: expectedRole,
    name,
    email,
    courses: readCourses(data.courses ?? root.courses),
  };
}

function readCourses(value: unknown): NormalizedLmsCourse[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new InvalidLmsResponseError();

  return value.map((course) => {
    const data = asObject(course);

    return {
      lmsCourseId: readRequiredString(data, ['course_id', 'id']),
      name: readRequiredString(data, ['course_name', 'name']),
      category: readOptionalString(data, ['category', 'course_category']),
    };
  });
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
    const value = data[key];

    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }

    if (typeof value === 'number' && Number.isFinite(value)) {
      return String(value);
    }
  }

  return undefined;
}

function normalizeRole(value: string): LmsUserRole | undefined {
  const role = value.trim().toLowerCase();

  if (role === 'student' || role === 'teacher' || role === 'admin') {
    return role;
  }

  return undefined;
}

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
  const isManagerOperation =
    expectedRole === 'admin'
      ? hasAdminManagerOperation(data) || hasAdminManagerOperation(root)
      : false;
  const isTechnicalSupport =
    expectedRole === 'admin'
      ? hasAdminTechnicalSupport(data) || hasAdminTechnicalSupport(root)
      : false;
  const isAcademic =
    expectedRole === 'admin'
      ? hasAdminAcademic(data) || hasAdminAcademic(root)
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
    isManagerOperation,
    isTechnicalSupport,
    isAcademic,
    courses: readCourses(
      data.courses ?? root.courses,
      root.admin ?? data.admin,
    ),
  };
}

export function parseLmsPhpArrayResponse(
  payload: string,
  expectedRole: LmsUserRole,
): NormalizedLmsUser | undefined {
  if (!/\bArray\s*\(/i.test(payload)) return undefined;

  const fields = userFields[expectedRole];
  const data: JsonObject = {};
  const keys = [
    ...fields.id,
    ...fields.name,
    ...fields.email,
    'fullaccese',
    'full_access',
    'fullAccess',
    'm_operation',
    'mOperation',
    'moperation',
    'm_op',
    'mOp',
    'operation_manager',
    'operationManager',
    'manager_operation',
    'managerOperation',
    'manager_op',
    'managerOp',
    'tec',
    'tech',
    'technical_support',
    'technicalSupport',
    'isTechnicalSupport',
    'manage-techers',
    'manage_teachers',
    'manageTeachers',
    'manage_teacher',
    'manageTeacher',
    'manage_techers',
    'manageTechers',
    'isAcademic',
  ];

  for (const key of keys) {
    const value = readPhpArrayValue(payload, key);
    if (value !== undefined) {
      data[key] = value;
    }
  }

  try {
    return parseLmsResponse(
      expectedRole === 'admin'
        ? { admin_name: [data] }
        : { [expectedRole]: data },
      expectedRole,
    );
  } catch {
    return undefined;
  }
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
      teacherLmsUserId: readOptionalString(data, [
        'teacher_id',
        'teacherId',
        'teacher',
        'te_id',
        't_id',
      ]),
      teacherName: readOptionalString(data, [
        'teacher_name',
        'teacherName',
        'teacher_shortname',
        'teacherShortname',
        'te_name',
      ]),
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

function hasAdminManagerOperation(data: JsonObject): boolean {
  const managerOperation = readOptionalNumber(data, [
    'm_operation',
    'mOperation',
    'moperation',
    'm_op',
    'mOp',
    'operation_manager',
    'operationManager',
    'manager_operation',
    'managerOperation',
    'manager_op',
    'managerOp',
  ]);

  return managerOperation === 1;
}

function hasAdminTechnicalSupport(data: JsonObject): boolean {
  const technicalSupport = readOptionalNumber(data, [
    'tec',
    'tech',
    'technical_support',
    'technicalSupport',
    'isTechnicalSupport',
  ]);

  return technicalSupport === 1;
}

function hasAdminAcademic(data: JsonObject): boolean {
  const manageTeachers = readOptionalNumber(data, [
    'manage-techers',
    'manage_teachers',
    'manageTeachers',
    'manage_teacher',
    'manageTeacher',
    'manage_techers',
    'manageTechers',
    'isAcademic',
  ]);

  return manageTeachers === 1;
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

function readPhpArrayValue(payload: string, key: string): string | undefined {
  const pattern = new RegExp(
    `\\[\\s*${escapeRegex(key)}\\s*\\]\\s*=>\\s*([^\\r\\n\\[]+)`,
    'i',
  );
  const value = pattern.exec(payload)?.[1]?.trim();

  return value
    ?.replace(/^["']|["']$/g, '')
    .replace(/\)+$/g, '')
    .trim();
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function normalizeRole(value: string): LmsUserRole | undefined {
  const role = value.trim().toLowerCase();

  if (role === 'student' || role === 'teacher' || role === 'admin') {
    return role;
  }

  return undefined;
}


export type LmsUserRole = 'student' | 'teacher' | 'admin';

export interface LmsLoginCredentials {
  role: LmsUserRole;
  username: string;
  password: string;
}

export interface NormalizedLmsCourse {
  lmsCourseId: string;
  name: string;
  category?: string;
  students?: NormalizedLmsStudent[];
}

export interface NormalizedLmsStudent {
  lmsUserId: string;
  name: string;
}

export interface NormalizedLmsUser {
  lmsUserId: string;
  role: LmsUserRole;
  name: string;
  email?: string;
  courses: NormalizedLmsCourse[];
}

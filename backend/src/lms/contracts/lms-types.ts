export type LmsUserRole = 'student' | 'teacher' | 'admin';

export interface LmsLoginCredentials {
  role: LmsUserRole;
  username: string;
  password: string;
  /**
   * Optional hints supplied by the caller to supplement course discovery.
   * Not part of the HTTP request body — added internally by the backend.
   */
  hints?: {
    /**
     * Active LMS course IDs already known to the backend database.
     * Used so admin course verification covers courses that are not
     * listed on the admin's LMS dashboard page.
     */
    knownCourseIds?: string[];
    /**
     * Authorization decision made by AuthService before LMS course discovery.
     * LMS response fields must not promote an admin independently.
     */
    hasFullAccess?: boolean;
    /**
     * Allows non-super-admin manager accounts to load every course/chat while
     * keeping destructive super-admin permissions disabled.
     */
    canViewAllCourses?: boolean;
  };
}

export interface NormalizedLmsCourse {
  lmsCourseId: string;
  name: string;
  category?: string;
  keyPersonLmsUserId?: string;
  keyPersonName?: string;
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
  isSuperAdmin?: boolean;
  isManagerOperation?: boolean;
  canViewAllCourses?: boolean;
  courses: NormalizedLmsCourse[];
}

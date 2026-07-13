import { InvalidLmsResponseError } from './eacc-lms.errors';
import { parseLmsResponse } from './eacc-lms.parser';

describe('parseLmsResponse', () => {
  it('normalizes a student response', () => {
    const user = parseLmsResponse(
      {
        st_id: '55',
        st_name: 'Esam Test',
        st_email: 'student@example.com',
        courses: [
          {
            course_id: '2191',
            course_name: 'Elementary Level - 3',
            category: 'English Adult',
          },
        ],
      },
      'student',
    );

    expect(user.role).toBe('student');
    expect(user.lmsUserId).toBe('55');
    expect(user.courses[0]?.lmsCourseId).toBe('2191');
  });

  it('normalizes a teacher response', () => {
    const user = parseLmsResponse(
      {
        data: {
          te_id: 12,
          te_name: 'Mohamed El-Sayad',
          te_email: 'teacher@example.com',
          courses: [],
        },
      },
      'teacher',
    );

    expect(user.role).toBe('teacher');
    expect(user.lmsUserId).toBe('12');
  });

  it('grants super-admin access only when the LMS full-access value is 1', () => {
    const fullAccessAdmin = parseLmsResponse(
      {
        admin_name: [
          {
            Admin_id: 92,
            Admin_shortname: 'developer',
            Fullaccess: '1',
          },
        ],
      },
      'admin',
    );
    const limitedAdmin = parseLmsResponse(
      {
        admin_name: [
          {
            Admin_id: 76,
            Admin_shortname: 'course admin',
            Fullaccess: '0',
          },
        ],
      },
      'admin',
    );

    expect(fullAccessAdmin.isSuperAdmin).toBe(true);
    expect(limitedAdmin.isSuperAdmin).toBe(false);
  });

  it('grants manager-operation access only when the LMS m_operation value is 1', () => {
    const managerAdmin = parseLmsResponse(
      {
        admin_name: [
          {
            id: 13,
            shortname: 'Eman',
            fullaccese: '0',
            m_operation: '1',
          },
        ],
      },
      'admin',
    );
    const contactPersonAdmin = parseLmsResponse(
      {
        admin_name: [
          {
            id: 91,
            shortname: 'testapp',
            fullaccese: '0',
            m_operation: '0',
          },
        ],
      },
      'admin',
    );

    expect(managerAdmin.isSuperAdmin).toBe(false);
    expect(managerAdmin.isManagerOperation).toBe(true);
    expect(contactPersonAdmin.isSuperAdmin).toBe(false);
    expect(contactPersonAdmin.isManagerOperation).toBe(false);
  });

  it('reads full access from the response root when admin identity is nested', () => {
    const admin = parseLmsResponse(
      {
        admin_name: [
          {
            Admin_id: 92,
            Admin_shortname: 'developer',
          },
        ],
        Fullaccess: '1',
      },
      'admin',
    );

    expect(admin.isSuperAdmin).toBe(true);
  });

  it('does not grant super-admin access for other truthy access values', () => {
    for (const Fullaccess of [2, 'true', true]) {
      const admin = parseLmsResponse(
        {
          admin_name: [
            {
              Admin_id: 92,
              Admin_shortname: 'developer',
              Fullaccess,
            },
          ],
        },
        'admin',
      );

      expect(admin.isSuperAdmin).toBe(false);
    }
  });

  it('rejects a mismatched response role', () => {
    expect(() =>
      parseLmsResponse(
        {
          id: '1',
          name: 'Wrong Role',
          role: 'teacher',
        },
        'student',
      ),
    ).toThrow(InvalidLmsResponseError);
  });
});

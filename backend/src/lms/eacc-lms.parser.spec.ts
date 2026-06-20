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

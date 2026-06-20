import { parseLmsDashboardHtml } from './eacc-lms.html-parser';

describe('parseLmsDashboardHtml', () => {
  const studentDashboard = `
    <html>
      <body>
        <h4>Welcome Test Student / ID: 3937</h4>
        <section>
          <h3>My Courses</h3>
        </section>
        <select name="wcid">
          <option value="100">Historical Report Course</option>
        </select>
      </body>
    </html>
  `;

  it('extracts the student identity from the dashboard heading', () => {
    const user = parseLmsDashboardHtml(studentDashboard, 'student');

    expect(user).toEqual({
      lmsUserId: '3937',
      role: 'student',
      name: 'Test Student',
      courses: [],
    });
  });

  it('does not treat report course options as active memberships', () => {
    const user = parseLmsDashboardHtml(studentDashboard, 'student');

    expect(user.courses).toEqual([]);
  });

  it('rejects unsupported teacher HTML in the student parser', () => {
    expect(() => parseLmsDashboardHtml(studentDashboard, 'teacher')).toThrow();
  });
});

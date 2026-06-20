import { parseTeacherDashboardHtml } from './eacc-lms.teacher-parser';

describe('parseTeacherDashboardHtml', () => {
  it('extracts the teacher identity from the dashboard sidebar', () => {
    const user = parseTeacherDashboardHtml(
      `
      <html>
        <body>
          <div class="user-panel mt-3 pb-3 mb-3 d-flex">
            <div class="image">
              <img src="https://lms.eacc-egy.com/teachers/721258-WhatsApp Image.jpeg" />
            </div>
            <div class="info">
              <a href="#" class="d-block">Mohamed El-Sayad</a>
            </div>
          </div>
        </body>
      </html>
      `,
      'teacher',
    );

    expect(user).toEqual({
      lmsUserId: '721258',
      role: 'teacher',
      name: 'Mohamed El-Sayad',
      courses: [],
    });
  });
});

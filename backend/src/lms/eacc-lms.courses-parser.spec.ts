import { parseStudentCoursesHtml } from './eacc-lms.courses-parser';

describe('parseStudentCoursesHtml', () => {
  it('extracts courses only from the Open tab', () => {
    const courses = parseStudentCoursesHtml(`
      <div id="Open">
        <a href="lms_details.php?wcid=2191">
          <div class="card">
            <div class="d-flex flex-column">
              <span>English Adult</span>
              <span>Elementary Level - 3</span>
              <span class="ratings">General English</span>
            </div>
          </div>
        </a>
      </div>
      <div id="Closed">
        <a href="lms_details_closed.php?wcid=2190">
          <div class="card">
            <div class="d-flex flex-column">
              <span>Preparation</span>
              <span>Preparation IELTS</span>
            </div>
          </div>
        </a>
      </div>
    `);

    expect(courses).toEqual([
      {
        lmsCourseId: '2191',
        name: 'Elementary Level - 3',
        category: 'English Adult',
      },
    ]);
  });

  it('returns no active courses when the Open tab is empty', () => {
    const courses = parseStudentCoursesHtml(`
      <div id="Open"><div class="row"></div></div>
      <div id="Closed">
        <a href="lms_details_closed.php?wcid=2191">Closed course</a>
      </div>
    `);

    expect(courses).toEqual([]);
  });
});

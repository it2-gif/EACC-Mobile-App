import { parseTeacherCourseStudentsHtml } from './eacc-lms.course-students-parser';

describe('parseTeacherCourseStudentsHtml', () => {
  it('extracts students from the teacher course Students tab', () => {
    const students = parseTeacherCourseStudentsHtml(`
      <div id="Students">
        <table>
          <tbody>
            <tr>
              <td>8303</td>
              <td>Victor Deng<br><div dir="rtl">Arabic name</div></td>
              <td><a href="add_grx.php?stid=8303&wcid=2203">Add Grade</a></td>
            </tr>
            <tr>
              <td>8301</td>
              <td>Another Student<br><div dir="rtl">Arabic name</div></td>
              <td><a href="add_grx.php?stid=8301&wcid=2203">Add Grade</a></td>
            </tr>
          </tbody>
        </table>
      </div>
    `);

    expect(students).toEqual([
      { lmsUserId: '8303', name: 'Victor Deng' },
      { lmsUserId: '8301', name: 'Another Student' },
    ]);
  });
});

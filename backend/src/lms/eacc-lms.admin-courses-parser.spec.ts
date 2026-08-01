import {
  parseAdminAccessFlagsHtml,
  parseAdminCourseIdsHtml,
  parseAdminCoursesHtml,
  parseAdminCourseTableSummary,
  parseAdminFromUserList,
} from './eacc-lms.admin-courses-parser';

describe('parseAdminFromUserList', () => {
  it('matches an admin by shortname when the LMS user table has no username column', () => {
    const admin = parseAdminFromUserList(
      `
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Shortname</th>
            <th>Fullaccese</th>
            <th>M Operation</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>14</td>
            <td>Esam</td>
            <td>1</td>
            <td>0</td>
          </tr>
        </tbody>
      </table>
      `,
      'esam',
    );

    expect(admin).toEqual(
      expect.objectContaining({
        id: '14',
        shortName: 'Esam',
        isSuperAdmin: true,
        isManagerOperation: false,
      }),
    );
  });

  it('finds admin detail links that use alternate admin id query names', () => {
    const admin = parseAdminFromUserList(
      `
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Shortname</th>
            <th>Username</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>13</td>
            <td>Eman</td>
            <td>eman.library</td>
            <td><a href="/hr/add_user.php?auid=13">Edit</a></td>
          </tr>
        </tbody>
      </table>
      `,
      'eman.library',
    );

    expect(admin).toEqual(
      expect.objectContaining({
        id: '13',
        shortName: 'Eman',
        detailsPath: '/hr/add_user.php?auid=13',
      }),
    );
  });

  it('reads admin role flags from an admin detail form', () => {
    const flags = parseAdminAccessFlagsHtml(`
      <form>
        <input type="hidden" name="fullaccese" value="1" />
        <input type="hidden" name="m_operation" value="0" />
      </form>
    `);

    expect(flags).toEqual({
      isSuperAdmin: true,
      isManagerOperation: false,
    });
  });

  it('does not treat unchecked full-access checkboxes as enabled', () => {
    const flags = parseAdminAccessFlagsHtml(`
      <form>
        <input type="checkbox" name="fullaccese" value="1" />
        <input type="checkbox" name="m_operation" value="1" checked />
      </form>
    `);

    expect(flags).toEqual({
      isSuperAdmin: false,
      isManagerOperation: true,
    });
  });

  it('reads checked role checkboxes after hidden zero fallback inputs', () => {
    const flags = parseAdminAccessFlagsHtml(`
      <form>
        <input type="hidden" name="fullaccese" value="0" />
        <input type="checkbox" name="fullaccese" value="1" />
        <input type="hidden" name="m_operation" value="0" />
        <input type="checkbox" name="m_operation" value="1" checked />
      </form>
    `);

    expect(flags).toEqual({
      isSuperAdmin: false,
      isManagerOperation: true,
    });
  });

  it('reads manager-operation aliases from admin detail forms', () => {
    const flags = parseAdminAccessFlagsHtml(`
      <form>
        <input type="hidden" name="fullaccese" value="0" />
        <input type="hidden" name="m_op" value="1" />
      </form>
    `);

    expect(flags).toEqual({
      isSuperAdmin: false,
      isManagerOperation: true,
    });
  });

  it('uses selected admin role option values instead of the first select option', () => {
    const flags = parseAdminAccessFlagsHtml(`
      <form>
        <select name="fullaccese">
          <option value="1">Yes</option>
          <option value="0" selected>No</option>
        </select>
        <select name="m_operation">
          <option value="1">Yes</option>
          <option value="0" selected>No</option>
        </select>
      </form>
    `);

    expect(flags).toEqual({
      isSuperAdmin: false,
      isManagerOperation: false,
    });
  });

  it('parses only open admin courses when the LMS page includes Open and Closed sections', () => {
    const html = `
      <div id="Open">
        <table>
          <thead>
            <tr><th>ID</th><th>Department</th><th>Course</th></tr>
          </thead>
          <tbody>
            <tr>
              <td>2203</td>
              <td>Preparation</td>
              <td><a href="/add_course.php?wcid=2203">Preparation IELTS</a></td>
            </tr>
          </tbody>
        </table>
      </div>
      <div id="Closed">
        <table>
          <tbody>
            <tr>
              <td>1999</td>
              <td>Old</td>
              <td><a href="/add_course.php?wcid=1999">Archived Course</a></td>
            </tr>
          </tbody>
        </table>
        <script>location.href = '/add_course.php?wcid=1888';</script>
      </div>
    `;

    expect(parseAdminCoursesHtml(html, '', '')).toEqual([
      expect.objectContaining({
        lmsCourseId: '2203',
        name: 'Preparation IELTS',
        category: 'Preparation',
      }),
    ]);
    expect(parseAdminCourseIdsHtml(html)).toEqual(['2203']);
  });

  it('prefers green working-course rows when the LMS filter page contains mixed statuses', () => {
    const html = `
      <table>
        <thead>
          <tr><th>ID</th><th>Department</th><th>Course</th></tr>
        </thead>
        <tbody>
          <tr style="background-color: #c3e6cb;">
            <td>2405</td>
            <td>English Youth</td>
            <td><a href="/add_course.php?wcid=2405">LEVEL - 3 Advanced</a></td>
          </tr>
          <tr class="table-danger">
            <td>1999</td>
            <td>Old</td>
            <td><a href="/add_course.php?wcid=1999">Closed Course</a></td>
          </tr>
          <tr class="table-warning">
            <td>2000</td>
            <td>Waiting</td>
            <td><a href="/add_course.php?wcid=2000">Upcoming Course</a></td>
          </tr>
        </tbody>
      </table>
    `;

    expect(parseAdminCoursesHtml(html, '', '')).toEqual([
      expect.objectContaining({
        lmsCourseId: '2405',
        name: 'LEVEL - 3 Advanced',
        category: 'English Youth',
      }),
    ]);
    expect(parseAdminCourseIdsHtml(html)).toEqual(['2405']);
  });

  it('uses the LMS working-courses table instead of unrelated page links', () => {
    const html = `
      <a href="/old.php?wcid=1111">Navigation Link</a>
      <table id="example2">
        <thead>
          <tr><th>ID</th><th>Department</th><th>Course</th></tr>
        </thead>
        <tbody>
          <tr class="table-success css1 odd">
            <td><span title="Enroled By: Hager">2405</span></td>
            <td>English Youth</td>
            <td><a href="/edit_course.php?wcid=2405">LEVEL - 3</a><br>Advanced</td>
            <td><a href="/view_students2.php?wcid=2405">Students</a></td>
            <td><a href="/del_Course.php?wcid=2405">Delete Course</a></td>
          </tr>
          <tr class="table-success css1 even">
            <td><span>2404</span></td>
            <td>English Youth</td>
            <td><a href="/edit_course.php?wcid=2404">LEVEL - 3</a><br>Upper-Intermediate</td>
            <td><a href="/view_students2.php?wcid=2404">Students</a></td>
            <td><a href="/del_Course.php?wcid=2404">Delete Course</a></td>
          </tr>
        </tbody>
      </table>
      <script>const stale = '/edit_course.php?wcid=9999';</script>
    `;

    expect(
      parseAdminCoursesHtml(html, '', '').map((course) => course.lmsCourseId),
    ).toEqual(['2405', '2404']);
    expect(parseAdminCourseIdsHtml(html)).toEqual(['2405', '2404']);
  });
  it('marks paginated LMS course tables as incomplete', () => {
    const html = `
      <h5>Total Classes: 82</h5>
      <table id="example2">
        <tbody>
          <tr class="table-success"><td>2405</td><td>English</td><td><a href="/edit_course.php?wcid=2405">Course A</a></td></tr>
          <tr class="table-success"><td>2404</td><td>English</td><td><a href="/edit_course.php?wcid=2404">Course B</a></td></tr>
        </tbody>
      </table>
      <div id="example2_info">Showing 1 to 2 of 82 entries</div>
    `;

    expect(parseAdminCourseTableSummary(html)).toEqual({
      totalCount: 82,
      visibleRowCount: 2,
      isComplete: false,
    });
  });
});

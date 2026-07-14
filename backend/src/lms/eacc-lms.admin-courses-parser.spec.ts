import {
  parseAdminAccessFlagsHtml,
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
});

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
});

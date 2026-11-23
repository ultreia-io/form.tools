# Security policy

Report vulnerabilities privately through [GitHub advisories](https://github.com/ultreia-io/form.tools/security/advisories/new).

If private reporting is unavailable, contact the maintainer at `dev@tchemit.fr`.

Do not include credentials, personal data, or confidential workbooks in public issues.

SQL files are trusted executable input. The consumer selects them and controls the database connection's permissions.

Bind values through the driver or backend; do not interpolate untrusted values into SQL text.

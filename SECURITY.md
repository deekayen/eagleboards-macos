# Security & privacy

Eagle Boards handles personal information about **minors**. Please read this
before your first commit.

## What is sensitive

| Data | Where it lives | Why it matters |
| --- | --- | --- |
| Youth names, units, emails | the data folder's dated `YYYY-MM-DD/` folders, exported reports | Personal information about minors |
| Adult names, emails, phones, board history | `adults.csv`, `Master_AdultHistory.csv` | Personal information, cumulative across years |
| SignUpGenius API key | the macOS keychain of the Mac running the app | Grants API access to the district's sign-ups |

Eagle Boards no longer asks for, imports or keeps a youth's birthdate or phone
number (SPEC.md D-7, D-8). Folders from earlier events may still hold them:
they are left in place, and never shown, sent to a tablet or exported.

The data folder is chosen by the operator and lives outside this repository.
Nothing in the repository or in a built app contains participant data or a key.

## Never commit these

`.gitignore` excludes spreadsheets and CSVs, dated folders,
`Master_AdultHistory*`, `*Board_Results*`, `config.properties` and `.env`.
`scripts/hooks/pre-commit` refuses a commit that stages any of them, or what
looks like a SignUpGenius key. Install it once per clone:

```bash
git config core.hooksPath scripts/hooks
```

**Do not bypass it with `--no-verify`.** What it stopped cannot be unpublished
once pushed.

## The API key

- Enter it in **Settings › SignUpGenius**. It is stored in the login keychain,
  not in the data folder or the app's preferences.
- SignUpGenius takes the key as a URL query parameter. Eagle Boards never logs
  a request URL or puts one in an error message.
- CI reads it from the `SUG_KEY` repository secret, only to check that the API
  still answers, and never prints what comes back.

## Network exposure

The sign-in station is plain HTTP with no authentication, meant for a trusted
venue network for the length of one event.

- **Only the sign-in pages are served.** The scheduler, records and settings
  are native windows, not pages, so there is nothing for someone at the door
  to browse to. `CheckInServerTests` asserts the Java app's operator paths
  return 404.
- **Responses are trimmed to what each page shows.** The lists at the door get
  names and units. An email lookup returns the fields its form fills in and
  nothing else, and there is no call that lists everyone's email address.
  Lookups are POSTs, so an address never lands in a URL on a shared tablet.
- Responses carry `Cache-Control: no-store`, so the tablet does not keep them.
- Run it on the venue network, never on a public interface or a port-forward,
  and quit it when the event ends.

## Working with real data

- Develop and test against synthetic data. Tests create their own throwaway
  folders; `EAGLEBOARDS_DATA_FOLDER` points the app at a scratch folder.
- Never load the real adult history into anything you are going to
  screenshot.
- Exported reports hold names and contact details. Keep them private.

## Reporting a vulnerability

Open a GitHub issue for anything non-sensitive. For something that would
expose participant data or the API key, contact the maintainer directly, and
do not include the affected data in your report.

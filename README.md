# Schedule FA Platform

Computes the **Schedule FA** disclosures in an Indian income-tax return for a
resident who holds foreign assets through a broker such as Vested — Table A3
(foreign equity and debt) and Table A2 (foreign custodial accounts) — from the
transaction statement the broker exports.

It is a calculation platform, not a spreadsheet converter. The broker reports
dollars; the return wants rupees at a prescribed reference rate, and the rate
that applies differs per field. Each figure arrives with the transactions
behind it, the rate used, the formula, and the caveats — written into a
thirteen-sheet workbook you can hand to a reviewer.

> Nothing here is tax advice. It computes figures and shows its working; the
> filing position is yours.

---

## Contents

- [The one rule to understand first](#the-one-rule-to-understand-first)
- [What it actually does](#what-it-actually-does)
- [Set up on a new computer](#set-up-on-a-new-computer)
- [Start it again later](#start-it-again-later)
- [Loading exchange rates](#loading-exchange-rates)
- [Loading prices](#loading-prices)
- [Using the web application](#using-the-web-application)
- [Using the command line](#using-the-command-line)
- [Running with Docker](#running-with-docker)
- [Running the tests](#running-the-tests)
- [Configuration](#configuration)
- [How the code is organised](#how-the-code-is-organised)
- [Rules, policies and the difference](#rules-policies-and-the-difference)
- [Known limitations](#known-limitations)

---

## The one rule to understand first

**A figure that cannot be computed is never reported as zero.**

Every amount carries one of four states:

| State | Meaning |
| --- | --- |
| `COMPLETE` | Computed from verified inputs. |
| `QUALIFIED` | Computed, but something about it is caveated — the caveat travels with the figure. |
| `NIL` | Genuinely zero. There were no dividends; there were no sales. |
| `UNAVAILABLE` | Could not be computed, and the reason is attached. |

`UNAVAILABLE` renders as the words **NOT AVAILABLE** on screen and in the
workbook, and puts an entry on a worklist telling you what to supply. It is
never a blank cell and never a `0`, because a blank in a Schedule FA cell
reads as *"I held nothing"* — a filing position you did not take.

The same principle applies to exchange rates and prices. If the rate for a
date is missing, the system says so. It does not interpolate, carry forward
silently, or substitute a nearby day without labelling it.

---

## What it actually does

Uploading a statement starts a pipeline of eleven stages:

1. **Read** the file, preserving the broker's exact digit strings. `1,234.50`
   is kept as those characters, not as a float, until it becomes a `Decimal`.
2. **Parse** it into a canonical ledger, detecting the broker and the header
   row rather than assuming a column layout.
3. **Resolve securities** against a master. An unknown ticker is flagged, not
   invented — there is no fabrication of an ISIN or an issuer country.
4. **Reconstruct lots** from the transaction history, matching disposals to
   acquisitions by the allocation method you chose.
5. **Reconcile** the reconstructed position against what the statement claims
   you hold, and report the difference if there is one.
6. **Resolve rates** from an immutable SBI TTBR dataset version.
7. **Value** each holding on every priced day, applying corporate actions.
8. **Convert** to rupees — and this is the subtle part. The *peak value* is
   searched in **rupees**, not dollars. A holding can reach its dollar high in
   March and its rupee high in September; the form asks for the rupee answer,
   so every day is valued and converted separately before the maximum is taken.
9. **Compute** the five reported figures per asset: initial value, peak value,
   closing value, income credited, gross proceeds.
10. **Validate**, producing a readiness verdict and a worklist of everything
    unsettled.
11. **Write** the workbook, with a derivation for every figure.

### The awkward cases it handles

| Situation | What happens |
| --- | --- |
| Shares sold that were bought before your earliest statement | The holding is recognised without inventing a purchase price. Cost-derived figures become `UNAVAILABLE`. |
| A stock split | Share count and per-share cost change; total cost does not. |
| The broker reports Jan–Dec, the tax year is Apr–Mar | Reporting periods are computed per assessment year, not assumed. |
| A date with two published rate sheets | Resolved by an explicit policy you choose, recorded on the run. |
| A ticker that changed | Corporate-action aware resolution rather than string matching. |

### Reproducibility

Identifiers are derived from content hashes, not from timestamps or counters.
Re-running the pipeline on identical inputs produces byte-identical output and
byte-identical identifiers. A calculation run pins the rule version, the rate
dataset *and its version*, the price dataset, and the hash of every source file.
Later rate corrections create a new run; they never alter an old one. That is
what makes a figure you filed in 2025 still explainable in 2028.

---

## Set up on a new computer

Do these steps once, after you clone the repository onto a laptop that has
never run this project. The clone contains the code only. It does not contain
Python packages, a database, or a secret key. Those are created on the machine
you are sitting at.

The commands below are for **Windows PowerShell**. On a Mac or Linux terminal,
use the short equivalents in each step.

### 1. Install Python

You need **Python 3.11 or newer**. 3.12 is the version this project was built
with.

1. Go to [python.org/downloads](https://www.python.org/downloads/) and install
   Python 3.12.
2. On the first installer screen, tick **Add python.exe to PATH**.
3. Finish the install, then open a new PowerShell window and check:

```powershell
python --version
```

You should see something like `Python 3.12.x`. If Windows says `python` is not
recognised, close PowerShell, open it again, and try `py --version`. Use
whichever of `python` or `py` works for the rest of these steps.

### 2. Install Git, if you do not already have it

You only need this to download the repository. If you already copied the
project folder onto the laptop by hand, skip to step 4.

Download Git from [git-scm.com](https://git-scm.com/downloads) and accept the
default options. Then check:

```powershell
git --version
```

### 3. Clone the repository

Pick a folder you own, for example your user folder, and download the code
into it. Replace the URL with your own repository address.

```powershell
cd $HOME
git clone https://github.com/YOUR-USERNAME/YOUR-REPO.git
cd YOUR-REPO
```

On a Mac or Linux the same two commands work. `cd YOUR-REPO` means "go into
the folder that was just created." Every later command assumes you are inside
that folder.

### 4. Create a virtual environment

A virtual environment is a private Python folder for this project, so its
packages do not mix with anything else on the laptop. It lives in `.venv` and
is not part of the GitHub repository. Create it on each machine.

```powershell
python -m venv .venv
```

Mac or Linux: the same command.

### 5. Turn the virtual environment on

You do this in every new terminal window before you run the app.

```powershell
.\.venv\Scripts\Activate.ps1
```

The start of the line should now show `(.venv)`.

If PowerShell refuses with a message about execution policy, run this once,
then try the activate command again:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Mac or Linux:

```bash
source .venv/bin/activate
```

### 6. Install the project's packages

This reads `pyproject.toml` and downloads the libraries the app needs
(FastAPI, the database tools, the spreadsheet reader, and the test tools).
It needs an internet connection. It only has to succeed once per machine.

```powershell
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
```

The `.[dev]` part also installs pytest, so you can run the tests. If you only
want to use the app and not the tests:

```powershell
python -m pip install -e .
```

Wait until it finishes without an error. A successful install ends with a line
saying the package was installed.

### 7. Create your settings file

`.env.example` is a blank form that is safe to keep on GitHub. `.env` is your
filled-in copy, and it stays on this laptop. Git is set up to ignore `.env`,
so a later commit will not upload your key.

```powershell
Copy-Item .env.example .env
```

Mac or Linux: `cp .env.example .env`

### 8. Make a secret key and put it in `.env`

The app uses this key to sign login tokens. It must be different on every
machine, and it must not be the placeholder text already in the file.

Generate one:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

A long random string is printed. Copy it.

Open `.env` in any text editor. Find this line:

```text
FA_SECRET_KEY=
```

Paste the string after the equals sign, with no quotes and no spaces:

```text
FA_SECRET_KEY=the-long-string-you-just-copied
```

Leave the other lines as they are. Saving the file is enough; there is no
further setup for the database address, because the default is a local SQLite
file created in the next step.

### 9. Create the database

This builds the empty tables (users, workspaces, uploaded files, calculation
runs, and so on). It creates `var/local.db` the first time. That file is your
local database. It is not on GitHub, and it should stay that way.

```powershell
python -m alembic upgrade head
```

You should see Alembic apply the revision named `initial schema`. If it says
the database is already at head, that is also fine: the tables exist.

### 10. Start the application

```powershell
python -m uvicorn backend.app.api.asgi:app --reload --port 8000
```

Leave this window open. `--reload` restarts the server when you change code.
When you want to stop it, click the window and press `Ctrl+C`.

### 11. Open it in a browser

Go to <http://127.0.0.1:8000/>.

1. Choose **Create one** and register. The password must be at least 12
   characters. The first account is an ordinary account; there is no separate
   admin login.
2. Create a workspace. The year it asks for is the **assessment year**, not
   the financial year. Income earned from April 2024 to March 2025 is assessed
   in **2025-26**.
3. Upload a broker statement and run a calculation.

A calculation will not produce rupee figures until you have imported an
exchange-rate file. That is a separate step, written under
[Loading exchange rates](#loading-exchange-rates). Until then the app still
starts, and you can create the account and the workspace.

Uploaded statements are stored in `var/storage`. The database is
`var/local.db`. Neither folder is uploaded by Git.

`http://127.0.0.1:8000/docs` is an interactive page that lists every API
endpoint. It is available in this local setup and hidden when the app is run
as production.

---

## Start it again later

You do not repeat the install. In a new PowerShell window:

```powershell
cd C:\path\to\the\cloned\folder
.\.venv\Scripts\Activate.ps1
python -m uvicorn backend.app.api.asgi:app --reload --port 8000
```

Then open <http://127.0.0.1:8000/>.

Mac or Linux: `source .venv/bin/activate` instead of the `Activate.ps1` line.

If you pulled new code from GitHub and the database tables changed, run this
once before starting the server:

```powershell
python -m alembic upgrade head
```

---

## Loading exchange rates

**A calculation cannot run without a rate dataset, and the system will not
invent a rate.** This is the one setup step that needs data from outside.
Finish [Set up on a new computer](#set-up-on-a-new-computer) first. The
commands below are run from the project folder on Windows and call the
virtual environment directly, so you do not have to activate it first. If
`.venv` is already activated, `python -m backend.app.cli` does the same job.

Get SBI TT Buying rates for the period you are filing — a CSV with a date
column and a rate column. Then:

```powershell
# See how your file is structured before importing it
.venv\Scripts\python.exe -m backend.app.cli profile-fx path\to\rates.csv

# Import it as an immutable dataset version
.venv\Scripts\python.exe -m backend.app.cli ingest-fx path\to\rates.csv `
    --dataset sbi-ttbr `
    --version 2025.1 `
    --source-id SBI_TTBR `
    --source-name "State Bank of India TT reference rates" `
    --source-url "https://sbi.co.in/..." `
    --fixed-currency USD `
    --date-column Date `
    --tt-buy-column "TT BUY"

# Confirm it covers your reporting period, day by day
.venv\Scripts\python.exe -m backend.app.cli fx-coverage `
    --dataset sbi-ttbr --version 2025.1 `
    --start 2024-04-01 --end 2025-03-31
```

Add `--dry-run` to the import to see what would be stored without writing it.

Datasets land in `data/fx/` as `<name>__<version>.fxdataset.json`, carrying a
content hash. **A version, once written, is immutable.** Re-importing the same
content is a no-op; re-importing *different* content under the same version is
refused — corrections become a new version, so a calculation already published
against the old one stays reproducible.

`fx-coverage` is worth running before every filing. A dataset that silently
lacks 11 March is a dataset that will produce `UNAVAILABLE` figures, and it is
better to find that out now.

---

## Loading prices

Peak and closing values need a daily price series. Drop a CSV per dataset into
`data/market/`:

```
data/market/us-equities-2024.csv
```

with columns for ticker, date, close (and optionally high, currency). Check it
before relying on it:

```powershell
.venv\Scripts\python.exe -m backend.app.cli inspect-prices data\market\us-equities-2024.csv
```

This prints coverage and gaps. Prices are treated as **unadjusted** and
corporate actions are applied by the engine — feeding in an already-adjusted
series will double-count a split.

You can run without a price dataset. Peak and closing values then come back as
`UNAVAILABLE` with the reason given, which is the honest answer.

---

## Using the web application

1. **Create a workspace.** One filer, one assessment year. Note that the field
   asks for the *assessment* year: income earned April 2024 to March 2025 is
   assessed in **2025-26**.
2. **Upload statements.** CSV or Excel. The original bytes are stored
   unchanged and every downstream figure is traceable to the file's content
   hash. Re-uploading the same file is recognised and not stored twice.
3. **Run a calculation.** Pick the rate dataset, the price dataset, and the
   four policy choices. Every one of them is recorded on the run.
4. **Read the figures.** Tables A3 and A2 as the form lays them out. Expand any
   row to see, per figure: the native amount, the rate and its date, the
   formula, the explanation, and any caveats.
5. **Work the worklist.** Each entry is something the engine could not settle
   alone. Some are waivable with a recorded reason; some — a missing rate, for
   instance — are not, because that is missing data rather than a judgement
   call. A reason is mandatory: an acknowledgement with no stated reason is
   indistinguishable from a mis-click a year later.
6. **Download the workbook.** This is the file to keep.

Decisions are stored against the workspace, not the run, and carried into
later runs. Fixing one statement does not mean re-deciding everything. A
carried decision whose underlying data changed is flagged for
reconfirmation rather than applied silently.

### Sharing a workspace

Owners can add people by email (the account must already exist):

| Role | Can |
| --- | --- |
| `VIEWER` | Read figures and download workpapers |
| `EDITOR` | Also upload statements and run calculations |
| `OWNER` | Also add and remove people |

A workspace you are not a member of returns **404, not 403** — a 403 would
confirm it exists and turn the endpoint into a way to enumerate other people's
workspace ids. The last owner cannot be removed: promote someone else first.

---

## Using the command line

The full pipeline without the web app, useful for a one-off:

```powershell
.venv\Scripts\python.exe -m backend.app.cli schedule-fa statement.xlsx `
    --fx-dataset sbi-ttbr --fx-version 2025.1 `
    --prices data\market\us-equities-2024.csv `
    --assessment-year 2025-26 `
    --workpaper out\workpaper.xlsx
```

Other commands, roughly in the order you would reach for them:

| Command | Answers |
| --- | --- |
| `inspect-broker <file>` | What sheets, columns, dates and activity labels does my statement really contain? |
| `brokers` | Which brokers are recognised, and how are their columns mapped? |
| `profile-fx <file>` | How is my rate file structured? |
| `ingest-fx <file>` | Import rates as an immutable dataset version. |
| `list-fx` | What rate datasets are installed? |
| `fx-coverage` | Does this dataset cover every day of my period? |
| `rules` | Which tax rule versions are registered, and which are verified? |
| `securities` | What is in the security master, and what does each record still need? |
| `resolve-securities <file>` | Which of my tickers resolve, and which do not? |
| `inspect-prices <file>` | What does my price file cover? |
| `holdings <file>` | Rebuild lots and reconcile them against the statement. |
| `schedule-fa <file>` | The whole thing. |

Run any of them with `--help` for the full option list.

---

## Running with Docker

This path downloads images, so use the quick start above if you would rather
not. It gives you PostgreSQL, migrations applied automatically, and the
calculation running in a background thread instead of inside the request.

```powershell
Copy-Item .env.example .env
# Set both FA_SECRET_KEY and FA_DB_PASSWORD in .env — neither has a default.

docker compose up --build
```

On <http://127.0.0.1:8000/>. Notes on what the compose file does deliberately:

- The database port is **not** published. Only the app can reach it.
- `migrate` runs to completion before `api` starts, so the server never comes
  up against a schema it does not match.
- `data/` is mounted **read-only**. The app resolves rates from it and must
  never be able to rewrite one.
- Uploads and workpapers live in the `storage` volume. **That is the volume to
  back up** — losing it loses the evidence behind a filed figure.
- The container runs as an unprivileged user and its health check hits the real
  `/api/v1/health`, which probes the database and the blob store rather than
  answering a constant.

---

## Running the tests

```powershell
.venv\Scripts\python.exe -m pytest                       # everything
.venv\Scripts\python.exe -m pytest tests/unit -q         # fast
.venv\Scripts\python.exe -m pytest tests/api -q          # HTTP layer
.venv\Scripts\python.exe -m pytest tests/property -q     # Hypothesis
.venv\Scripts\python.exe -m pytest --cov=backend --cov-report=term-missing
```

Linting and types:

```powershell
.venv\Scripts\python.exe -m ruff check .
.venv\Scripts\python.exe -m mypy backend
```

Worth knowing what some of these suites are for:

- `tests/property` generates money strings and formula-injection payloads
  rather than listing examples. It has already found a real bug: Excel's
  accounting format `$(1,234.56)` was being rejected, which would have thrown
  out every negative amount in an Excel-exported statement.
- `tests/integration/test_determinism.py` runs the pipeline twice and compares
  bytes, including with the system clock moved years forward. It exists
  because a fixture was stamping ZIP entries with `time.localtime()`, which
  made identifiers change between runs and quietly broke decision
  carry-forward.
- `tests/unit/test_report_safety.py` asserts against the raw sheet XML that no
  `<f>` element — a formula — ever reaches a generated workbook.

---

## Configuration

Everything is an environment variable prefixed `FA_`, read from `.env`. See
[`.env.example`](.env.example) for the annotated list. The ones that matter:

| Variable | Default | Notes |
| --- | --- | --- |
| `FA_SECRET_KEY` | placeholder | Signs session and download tokens. **Generate your own.** Changing it signs everyone out. |
| `FA_ENVIRONMENT` | `local` | `production` refuses to start on a placeholder key or on SQLite, and hides `/docs`. |
| `FA_DATABASE_URL` | SQLite in `var/` | PostgreSQL required in production. |
| `FA_STORAGE_ROOT` | `var/storage` | Uploads and workpapers. Back this up. |
| `FA_DATA_ROOT` | `data` | Rate and price datasets. |
| `FA_JOB_BACKEND` | `inline` | `thread` to run calculations in the background. |
| `FA_MAX_UPLOAD_BYTES` | 25 MB | Enforced before the body is read into memory. |
| `FA_ALLOW_OUTBOUND_INGESTION` | `false` | No user calculation can ever trigger a live fetch. |

### Security posture, briefly

Passwords are argon2id. Sessions are JWTs with a distinct audience from
download tokens, so a download link cannot be replayed as a session. Download
links are short-lived because the credential travels in the URL and is
therefore in browser history and proxy logs. Authorisation goes through a
single `authorise()` function surfaced as a FastAPI dependency, so a route
that forgets it fails to resolve a workspace at all rather than serving one
openly. The frontend contains no inline script or style and uses no
`innerHTML`, so it runs under a strict Content-Security-Policy and a security
name containing markup is displayed rather than executed. Generated files get
the same treatment from the other direction: XLSX cells are forced to string
type and CSV fields are prefixed, with every alteration reported in the
bundle's manifest, so an uploaded `=cmd|...` cannot execute in the reviewer's
spreadsheet.

---

## How the code is organised

```
backend/app/
  core/          decimal money, error catalogue, validation levels, config
  io/            raw XLSX/CSV reading that preserves exact digit strings
  brokers/       BrokerParser interface, registry, Vested parser
  domain/        canonical transaction ledger
  tax/           reporting periods, versioned rule registry, form schemas
  fx/            SBI TTBR records, immutable dataset versions, rate selection
  securities/    security master and resolution (no fabrication)
  marketdata/    price providers, snapshots, corporate actions
  lots/          lot reconstruction, allocation methods, reconciliation
  schedulefa/    the A2/A3 calculation engine and its explanations
  validation/    validation engine, issue collection, decision carry-forward
  reports/       XLSX and CSV workpaper writers, injection safety
  db/            SQLAlchemy models, session handling, Alembic migrations
  auth/          passwords, tokens, the single authorisation chokepoint
  storage/       content-addressed blob store
  jobs/          inline and threaded run execution
  audit/         append-only trail
  api/           FastAPI routes, schemas, dependencies, error handling
frontend/        dependency-free browser client — no framework, no build step
data/            rate datasets, price CSVs, rule versions, security master
docs/            design notes per subsystem
tests/           unit, property, golden, integration, api
```

The frontend has no build step on purpose. A tax workpaper has to be
reproducible years after filing, and a `node_modules` tree is the least
reproducible thing in a repository. It also means no layer between the API
response and the text node can reformat a decimal string.

Deeper design notes live in `docs/`:
[`schedule-fa-engine.md`](docs/schedule-fa-engine.md),
[`lot-engine.md`](docs/lot-engine.md),
[`market-data.md`](docs/market-data.md),
[`validation-and-issues.md`](docs/validation-and-issues.md),
[`workpapers.md`](docs/workpapers.md),
[`security-master.md`](docs/security-master.md),
[`adding-a-broker.md`](docs/adding-a-broker.md).

### Adding a broker

Implement `BrokerParser`, register it, and add a fixture. The core does not
change. See [`docs/adding-a-broker.md`](docs/adding-a-broker.md).

---

## Rules, policies and the difference

The code distinguishes these carefully, and so should you when reading a
workpaper.

A **rule** is something the law or the form prescribes — which figures Table
A3 requires, that values are reported in rupees, that the reporting period
follows the assessment year. Rules are versioned per assessment year and
carry a `verified` flag saying whether they have been checked against the
published form. An unverified rule version still works, but every screen and
every report it touches says so.

A **policy** is a choice the law leaves open. Schedule FA requires a peak
value without prescribing how often to revalue or which market-data vendor to
trust. So these are yours, and each is recorded on the run and printed in the
workpaper:

| Policy | Options |
| --- | --- |
| Lot allocation | `FIFO`, `LIFO`, `HIGHEST_COST_FIRST` |
| Valuation point | `DAILY_CLOSE`, `DAILY_HIGH` |
| Peak search frequency | `EVERY_PRICED_DAY`, `MONTH_END`, `QUARTER_END` |
| Duplicate rate sheets | `LATEST_PUBLICATION`, `EARLIEST_PUBLICATION`, `HIGHEST_RATE`, `LOWEST_RATE`, `FAIL` |

FIFO and daily close are defaults, not assertions about what the law requires.
Month-end peak search is cheaper and **materially different** from revaluing
every priced day, which is why it is labelled rather than silently chosen.

---

## Known limitations

Stated plainly, because a limitation you know about is manageable.

**A broker re-export loses your decisions.** A transaction's identity is
derived from the source file's hash, the sheet name and the row number. If
your broker re-exports the same period with one extra row near the top, every
row number below it shifts, so every transaction gets a new id and every
decision you recorded against one becomes `OBSOLETE`. You will be asked to
re-decide. The decisions are not lost — they remain in the audit trail — but
they stop applying. Keying on economic content instead would be the fix, and
it is not implemented.

**Rule versions need verifying against the published form.** The registry
ships rule versions for AY 2024-25 through 2026-27 with a `verified` flag.
Check that flag before filing on a figure. Run `rules` to see the current
state.

**No income-tax computation.** This produces Schedule FA disclosures. Capital
gains, dividend taxation, foreign tax credit and Schedule TR are out of scope.

**One broker parser.** Vested. The interface is stable and adding another does
not touch the core, but only one exists today.

**Prices must be unadjusted.** An already-adjusted series will double-count
corporate actions. `inspect-prices` will not catch this for you.

**No rate ingestion from source.** Outbound network access is off by default
and rate files are imported by an operator on purpose. There is no scheduled
fetch of SBI rates; you import them and the dataset version is then frozen.

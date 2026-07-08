# Job Hunter - Automated SRE Job Scraper

A PowerShell + Kiro automation that scrapes ATS platforms for SRE roles, then uses Kiro to score and notify you of high-match opportunities.

**Zero API fees. Scoring and email powered by your Kiro Pro subscription.**

## How It Works

The system runs in two phases:

### Phase 1: Scrape (automated, runs on schedule)

```
Task Scheduler (daily 7 AM)
    → Run-JobHunter.ps1
    → Scrapes 6 ATS platforms
    → Filters by title/level keywords
    → Deduplicates against previously seen jobs
    → Saves new jobs to data/pending_scoring.json
```

### Phase 2: Score + Notify (in Kiro, when you open it)

```
You open Kiro
    → Ask: "score my pending jobs"
    → Kiro reads pending_scoring.json
    → Scores each job 1-100 against your profile
    → Buckets: Apply Today (85+), Worth Looking (70-84), Skip (<70)
    → Generates HTML report
    → Sends email via Gmail MCP with top matches
```

## Quick Start

### 1. Configure

Edit `config.json`:

- Add/remove companies from each ATS section
- Adjust `profile` to match your background and skills
- Adjust `title_filters` and `exclude_keywords` as needed

Set environment variables:
```powershell
# Required for email notifications
[Environment]::SetEnvironmentVariable("JOBHUNTER_GMAIL", "your-email@gmail.com", "User")
```

### 2. Run the scraper

```powershell
.\Run-JobHunter.ps1

# Verbose output for debugging
.\Run-JobHunter.ps1 -Verbose
```

### 3. Score in Kiro

Open this project in Kiro and say:

> "score my pending jobs"

Kiro will read the scraped jobs, score them against your profile, generate a report, and offer to email you the top matches.

### 4. Schedule the scraper (daily at 7 AM)

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\Users\jetny\OneDrive\job-hunter\Run-JobHunter.ps1`""
$trigger = New-ScheduledTaskTrigger -Daily -At 7am
Register-ScheduledTask -TaskName "JobHunter" -Action $action -Trigger $trigger -Description "Daily SRE job scraper"
```

## Supported Platforms

| Platform | Method | Auth Required | Config File |
|----------|--------|---------------|-------------|
| Greenhouse | JSON API | No | config.json |
| Lever | JSON API | No | config.json |
| Ashby | JSON API | No | config.json |
| SmartRecruiters | JSON API | No | config.json |
| Workday | HTML scraping | No | config.json |
| iCIMS | HTML scraping | No | config.json |
| Generic Career Pages | HTML scraping + JSON-LD | No | career_pages.json |

## Scoring Criteria

When you ask Kiro to score jobs, it evaluates each one on 5 factors:

| Factor | Weight | What it checks |
|--------|--------|----------------|
| Title/Level Match | 25% | SRE/Reliability title at Principal/Staff/Senior level |
| Skills Match | 30% | Dynatrace, Terraform, PagerDuty, Azure DevOps, PowerShell, observability |
| Salary Fit | 20% | >= $180k listed or estimated |
| Remote/Location | 15% | Remote-friendly or US-based |
| Company Fit | 10% | Good engineering culture, right size (50-10k employees) |

## Kiro Commands

These are the things you can ask Kiro to do in this project:

| Command | What it does |
|---------|--------------|
| "score my pending jobs" | Score unscored jobs, generate report, prepare email |
| "send the pending job hunter email" | Send the Apply Today email via Gmail |
| Click **Send Job Hunter Email** hook | Same as above, via the hook button |

## Adding Companies

### ATS-specific (API-based, most reliable)

For API-based platforms, add the company slug to `config.json`:
```json
"greenhouse": ["hashicorp", "datadog", "newcompany"],
"lever": ["netflix", "figma", "anothercompany"]
```

For Workday/iCIMS, add an object with the search URL:
```json
"workday": [
  { "name": "CompanyName", "url": "https://company.wd5.myworkdaysite.com/search?q=sre" }
]
```

### Generic career pages (any ATS, broader coverage)

Add any company's careers search URL to `career_pages.json`:
```json
{ "name": "Stripe", "url": "https://stripe.com/jobs/search?query=site+reliability" }
```

This works regardless of what ATS the company uses. The scraper searches the page HTML for links matching your title filters and extracts any JSON-LD structured job data.

### Detecting a company's ATS

Use `Find-CompanyATS.ps1` to identify which ATS a company uses:
```powershell
.\Find-CompanyATS.ps1 -Url "https://careers.company.com"
.\Find-CompanyATS.ps1 -CompanyName "Datadog"
```

If the ATS is supported (Greenhouse, Lever, Ashby, SmartRecruiters), add the slug to `config.json` for reliable API-based scraping. Otherwise, add the careers URL to `career_pages.json`.

## Email Setup

Email is sent through your Gmail account via Kiro's Google Workspace MCP integration. No SMTP credentials needed.

Set the environment variable with your Gmail address:
```powershell
[Environment]::SetEnvironmentVariable("JOBHUNTER_GMAIL", "your-email@gmail.com", "User")
```

Make sure the Google Workspace MCP is connected in Kiro.

## File Structure

```
job-hunter/
├── Run-JobHunter.ps1           # Scraper (runs on schedule)
├── Find-CompanyATS.ps1         # Utility: detect a company's ATS
├── Send-PendingEmail.ps1       # Shows pending email status
├── config.json                 # ATS-specific company list + settings
├── career_pages.json           # Generic career page URLs (any ATS)
├── resume.md                   # Your resume (used for scoring context)
├── Luke_Calderone_Resume.pdf   # Original PDF resume
├── README.md
├── .kiro/
│   └── steering/
│       └── job-scoring.md      # Scoring instructions for Kiro
├── modules/
│   ├── Get-GreenhouseJobs.ps1
│   ├── Get-LeverJobs.ps1
│   ├── Get-AshbyJobs.ps1
│   ├── Get-SmartRecruiterJobs.ps1
│   ├── Get-WorkdayJobs.ps1
│   ├── Get-ICIMSJobs.ps1
│   ├── Get-CareerPageJobs.ps1  # Generic scraper (any career page)
│   ├── Export-HtmlReport.ps1
│   ├── Send-JobNotification.ps1
│   ├── Invoke-LLMScoring.ps1   # Legacy, not used
│   └── JobDatabase.ps1
├── data/
│   ├── jobs.json               # Job database (auto-created)
│   ├── pending_scoring.json    # Jobs awaiting Kiro scoring
│   ├── scored_results.json     # Scored output
│   └── pending_email.json      # Email ready to send
└── reports/
    └── report_2026-07-08.html  # HTML report after scoring
```

## Cost

**$0 extra.** Scraping is free (public APIs). Scoring and email use your existing Kiro Pro subscription.

## Data Retention

The job database (`data/jobs.json`) auto-prunes on every run:
- **Job records**: deleted after 90 days (configurable in `Run-JobHunter.ps1`)
- **Dedup index** (`seen_ids`): kept forever so you never re-process the same job
- **Pending scoring**: accumulates across daily runs until you score, then clears

This keeps the database performant even over months of searching.

## Development

This repo is hosted on GitHub at `jetnyyanks-sudo/job-hunter`.

```powershell
# Clone
git clone https://github.com/jetnyyanks-sudo/job-hunter.git

# Push changes
git add .
git commit -m "description"
git push
```

The `.gitignore` excludes personal data (resume, job database, reports) from the repo.

function Initialize-JobDatabase {
    <#
    .SYNOPSIS
        Creates the SQLite database and tables if they don't exist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath
    )

    # Ensure the data directory exists
    $dataDir = Split-Path $DatabasePath -Parent
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    # Use System.Data.SQLite or Microsoft.Data.Sqlite
    # For simplicity, we'll use a flat-file approach with JSON as fallback
    # if SQLite assemblies aren't available

    # Try to load SQLite (silently - JSON fallback is fine)
    $sqliteAvailable = $false
    $sqlitePath = "$PSScriptRoot\..\lib\System.Data.SQLite.dll"
    if (Test-Path $sqlitePath) {
        try {
            Add-Type -Path $sqlitePath -ErrorAction SilentlyContinue
            $sqliteAvailable = $true
        }
        catch { }
    }

    if (-not $sqliteAvailable) {
        try {
            [System.Reflection.Assembly]::Load("Microsoft.Data.Sqlite") | Out-Null
            $sqliteAvailable = $true
        }
        catch {
            Write-Verbose "SQLite not available, using JSON file database"
        }
    }

    if (-not $sqliteAvailable) {
        # Fallback: use JSON file
        $jsonDbPath = $DatabasePath -replace '\.db$', '.json'
        if (-not (Test-Path $jsonDbPath)) {
            @{
                jobs    = @()
                scores  = @()
                seen_ids = @()
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonDbPath -Encoding UTF8
        }
        return @{ Type = "json"; Path = $jsonDbPath }
    }

    # SQLite initialization
    $connectionString = "Data Source=$DatabasePath;Version=3;"
    $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    $connection.Open()

    $createTablesSql = @"
CREATE TABLE IF NOT EXISTS jobs (
    job_id TEXT PRIMARY KEY,
    source TEXT,
    company TEXT,
    title TEXT,
    location TEXT,
    url TEXT,
    posted_date TEXT,
    description TEXT,
    salary TEXT,
    first_seen TEXT,
    score INTEGER DEFAULT 0,
    score_reason TEXT DEFAULT '',
    skills_matched TEXT DEFAULT '',
    salary_estimate TEXT DEFAULT '',
    bucket TEXT DEFAULT 'unscored'
);

CREATE TABLE IF NOT EXISTS run_log (
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_date TEXT,
    jobs_found INTEGER,
    new_jobs INTEGER,
    high_score_jobs INTEGER
);
"@

    $command = $connection.CreateCommand()
    $command.CommandText = $createTablesSql
    $command.ExecuteNonQuery() | Out-Null
    $connection.Close()

    return @{ Type = "sqlite"; Path = $DatabasePath; ConnectionString = $connectionString }
}

function Test-JobSeen {
    <#
    .SYNOPSIS
        Checks if a job has already been processed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Database,

        [Parameter(Mandatory)]
        [string]$JobId
    )

    if ($Database.Type -eq "json") {
        $data = Get-Content -Path $Database.Path -Raw | ConvertFrom-Json
        return ($data.seen_ids -contains $JobId)
    }

    # SQLite
    $connection = New-Object System.Data.SQLite.SQLiteConnection($Database.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = "SELECT COUNT(*) FROM jobs WHERE job_id = @jobId"
    $command.Parameters.AddWithValue("@jobId", $JobId) | Out-Null
    $count = $command.ExecuteScalar()
    $connection.Close()
    return ($count -gt 0)
}

function Save-Job {
    <#
    .SYNOPSIS
        Saves a job and its score to the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Database,

        [Parameter(Mandatory)]
        [PSCustomObject]$Job,

        [PSCustomObject]$Score
    )

    $bucket = "review"
    if ($Score -and $Score.Score -ge 85) { $bucket = "apply_today" }
    elseif ($Score -and $Score.Score -ge 70) { $bucket = "worth_looking" }
    elseif ($Score -and $Score.Score -lt 50) { $bucket = "skip" }

    if ($Database.Type -eq "json") {
        $data = Get-Content -Path $Database.Path -Raw | ConvertFrom-Json

        # Add to seen_ids
        $seenIds = [System.Collections.ArrayList]@($data.seen_ids)
        $seenIds.Add($Job.JobId) | Out-Null

        # Add job record
        $jobsList = [System.Collections.ArrayList]@($data.jobs)
        $jobRecord = @{
            job_id          = $Job.JobId
            source          = $Job.Source
            company         = $Job.Company
            title           = $Job.Title
            location        = $Job.Location
            url             = $Job.Url
            posted_date     = $Job.PostedDate.ToString("yyyy-MM-dd")
            salary          = $Job.Salary
            first_seen      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            score           = if ($Score) { $Score.Score } else { 0 }
            score_reason    = if ($Score) { $Score.Reason } else { "" }
            skills_matched  = if ($Score) { $Score.SkillsMatched } else { "" }
            salary_estimate = if ($Score) { $Score.SalaryEstimate } else { "" }
            bucket          = $bucket
        }
        $jobsList.Add($jobRecord) | Out-Null

        @{
            jobs     = $jobsList.ToArray()
            scores   = $data.scores
            seen_ids = $seenIds.ToArray()
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $Database.Path -Encoding UTF8

        return
    }

    # SQLite
    $connection = New-Object System.Data.SQLite.SQLiteConnection($Database.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @"
INSERT OR REPLACE INTO jobs (job_id, source, company, title, location, url, posted_date, description, salary, first_seen, score, score_reason, skills_matched, salary_estimate, bucket)
VALUES (@jobId, @source, @company, @title, @location, @url, @postedDate, @description, @salary, @firstSeen, @score, @scoreReason, @skillsMatched, @salaryEstimate, @bucket)
"@
    $command.Parameters.AddWithValue("@jobId", $Job.JobId) | Out-Null
    $command.Parameters.AddWithValue("@source", $Job.Source) | Out-Null
    $command.Parameters.AddWithValue("@company", $Job.Company) | Out-Null
    $command.Parameters.AddWithValue("@title", $Job.Title) | Out-Null
    $command.Parameters.AddWithValue("@location", $Job.Location) | Out-Null
    $command.Parameters.AddWithValue("@url", $Job.Url) | Out-Null
    $command.Parameters.AddWithValue("@postedDate", $Job.PostedDate.ToString("yyyy-MM-dd")) | Out-Null
    $command.Parameters.AddWithValue("@description", $Job.Description) | Out-Null
    $command.Parameters.AddWithValue("@salary", $Job.Salary) | Out-Null
    $command.Parameters.AddWithValue("@firstSeen", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) | Out-Null
    $command.Parameters.AddWithValue("@score", $(if ($Score) { $Score.Score } else { 0 })) | Out-Null
    $command.Parameters.AddWithValue("@scoreReason", $(if ($Score) { $Score.Reason } else { "" })) | Out-Null
    $command.Parameters.AddWithValue("@skillsMatched", $(if ($Score) { $Score.SkillsMatched } else { "" })) | Out-Null
    $command.Parameters.AddWithValue("@salaryEstimate", $(if ($Score) { $Score.SalaryEstimate } else { "" })) | Out-Null
    $command.Parameters.AddWithValue("@bucket", $bucket) | Out-Null
    $command.ExecuteNonQuery() | Out-Null
    $connection.Close()
}

function Get-ApplyTodayJobs {
    <#
    .SYNOPSIS
        Returns all jobs in the "apply_today" bucket from the current run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Database,

        [string]$Since = (Get-Date).ToString("yyyy-MM-dd")
    )

    if ($Database.Type -eq "json") {
        $data = Get-Content -Path $Database.Path -Raw | ConvertFrom-Json
        return $data.jobs | Where-Object { $_.bucket -eq "apply_today" -and $_.first_seen -ge $Since }
    }

    # SQLite
    $connection = New-Object System.Data.SQLite.SQLiteConnection($Database.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = "SELECT * FROM jobs WHERE bucket = 'apply_today' AND first_seen >= @since ORDER BY score DESC"
    $command.Parameters.AddWithValue("@since", $Since) | Out-Null
    $reader = $command.ExecuteReader()

    $jobs = @()
    while ($reader.Read()) {
        $jobs += [PSCustomObject]@{
            JobId          = $reader["job_id"]
            Source         = $reader["source"]
            Company        = $reader["company"]
            Title          = $reader["title"]
            Location       = $reader["location"]
            Url            = $reader["url"]
            Score          = $reader["score"]
            ScoreReason    = $reader["score_reason"]
            SkillsMatched  = $reader["skills_matched"]
            SalaryEstimate = $reader["salary_estimate"]
        }
    }
    $connection.Close()
    return $jobs
}

function Invoke-DatabaseCleanup {
    <#
    .SYNOPSIS
        Prunes old job records while preserving the dedup index.
    .DESCRIPTION
        Removes full job records older than the retention period but keeps their
        IDs in seen_ids so they're never re-processed. This keeps the database
        performant over months of use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Database,

        [int]$RetentionDays = 90
    )

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays).ToString("yyyy-MM-dd")

    if ($Database.Type -eq "json") {
        $data = Get-Content -Path $Database.Path -Raw | ConvertFrom-Json

        $originalCount = $data.jobs.Count
        $recentJobs = @($data.jobs | Where-Object { $_.first_seen -ge $cutoffDate })
        $prunedCount = $originalCount - $recentJobs.Count

        if ($prunedCount -gt 0) {
            @{
                jobs     = $recentJobs
                scores   = $data.scores
                seen_ids = $data.seen_ids  # Keep ALL seen IDs for dedup
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $Database.Path -Encoding UTF8
            Write-Host "  Pruned $prunedCount job records older than $RetentionDays days (kept $($recentJobs.Count) recent)" -ForegroundColor DarkGray
            Write-Host "  Dedup index: $($data.seen_ids.Count) IDs preserved" -ForegroundColor DarkGray
        }
        else {
            Write-Verbose "No records to prune (all within $RetentionDays days)"
        }
        return
    }

    # SQLite
    $connection = New-Object System.Data.SQLite.SQLiteConnection($Database.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = "DELETE FROM jobs WHERE first_seen < @cutoff"
    $command.Parameters.AddWithValue("@cutoff", $cutoffDate) | Out-Null
    $deleted = $command.ExecuteNonQuery()
    $connection.Close()

    if ($deleted -gt 0) {
        Write-Host "  Pruned $deleted job records older than $RetentionDays days" -ForegroundColor DarkGray
    }
}

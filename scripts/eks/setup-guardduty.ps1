<#
.SYNOPSIS
  Enable AWS GuardDuty (if not already enabled) and pull findings.

.PREREQUISITES
  - AWS Tools for PowerShell installed:
      Install-Module -Name AWSPowerShell -Scope CurrentUser
  - AWS credentials/profile configured (aws configure or AWS Toolkit)
#>

param(
    # One or more AWS regions to process
    [string[]]$Regions = @("us-east-1"),

    # Optional AWS named profile
    [string]$ProfileName
)

foreach ($region in $Regions) {
    Write-Host "=== Processing region: $region ===" -ForegroundColor Cyan

    # Common params for all AWS cmdlets in this region
    $commonParams = @{
        Region = $region
    }
    if ($ProfileName) {
        $commonParams.ProfileName = $ProfileName
    }

    try {
        # 1) Check for existing GuardDuty detector
        $detectorIds = Get-GDDetector @commonParams

        if (-not $detectorIds -or $detectorIds.Count -eq 0) {
            Write-Host "No GuardDuty detector found in $region. Creating and enabling..." -ForegroundColor Yellow

            # 2) Create (enable) GuardDuty
            $detectorId = New-GDDetector @commonParams `
                -Enable $true `
                -FindingPublishingFrequency FIFTEEN_MINUTES

            Write-Host "Created GuardDuty detector: $detectorId" -ForegroundColor Green
        }
        else {
            $detectorId = $detectorIds[0]
            Write-Host "GuardDuty already enabled. Detector ID: $detectorId" -ForegroundColor Green
        }

        # 3) Get finding IDs
        Write-Host "Retrieving GuardDuty findings in $region..." -ForegroundColor Cyan

        $findingIds = Get-GDFindings @commonParams -DetectorId $detectorId

        if (-not $findingIds -or $findingIds.Count -eq 0) {
            Write-Host "No findings currently in $region." -ForegroundColor Yellow
            continue
        }

        # 4) Get full finding details
        $findings = Get-GDFinding @commonParams -DetectorId $detectorId -FindingId $findingIds

        # 5) Show a simple summary table
        $findings |
            Select-Object `
                Id,
                Type,
                Severity,
                Service.Action.ActionType,
                Resource.ResourceType,
                CreatedAt |
            Sort-Object Severity -Descending |
            Format-Table -AutoSize

        # 6) Optionally export to JSON per region
        $outputPath = "GuardDuty-Findings-$region.json"
        $findings | ConvertTo-Json -Depth 8 | Out-File -FilePath $outputPath -Encoding UTF8
        Write-Host "Findings exported to $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Error processing region ${region}: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

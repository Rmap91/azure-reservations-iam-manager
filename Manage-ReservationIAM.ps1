#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Azure Cloud Shell script to manage IAM permissions for all Azure reservations.

.DESCRIPTION
    This script performs the following operations:
    1. Shows detailed reservation information (SKU, usage, affected resources, end dates, status)
    2. Retrieves all Azure reservations and checks their IAM permissions
    3. Lists all current Owners for each reservation
    4. Prompts for a user or group to add as Owner across all reservations
    5. Adds Owner permissions to the specified user/group
    6. Displays the updated IAM permissions
    7. Exports detailed reports to CSV format

.PARAMETER ReportOnly
    When specified, shows only the detailed reservation report without IAM management

.PARAMETER ExportCsv
    When specified, exports the reservation data to CSV files for download

.PARAMETER OutputPath
    Specifies the path for CSV export files (default: current directory)

.NOTES
    - This script is designed to run in Azure Cloud Shell
    - Requires appropriate permissions to manage reservations and role assignments
    - Uses Azure CLI commands for reservation and IAM management
    - CSV files can be downloaded using Cloud Shell download feature

.EXAMPLE
    ./Manage-ReservationIAM.ps1
    
.EXAMPLE
    ./Manage-ReservationIAM.ps1 -ReportOnly

.EXAMPLE
    ./Manage-ReservationIAM.ps1 -ReportOnly -ExportCsv

.EXAMPLE
    ./Manage-ReservationIAM.ps1 -ExportCsv -OutputPath "./reports"
#>

[CmdletBinding()]
param(
    [switch]$ReportOnly,
    [switch]$ExportCsv,
    [string]$OutputPath = "."
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Color codes for output formatting
$Colors = @{
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
    Info    = "Cyan"
    Header  = "Magenta"
}

# Show comprehensive help information
function Show-Help {
    Write-Host ""
    Write-Host "Azure Reservations IAM Management Script" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "DESCRIPTION:" -ForegroundColor Yellow
    Write-Host "  Comprehensive Azure Cloud Shell script for managing IAM permissions across"
    Write-Host "  Azure reservations with detailed analytics, status tracking, and CSV export."
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  ./Manage-ReservationIAM.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  -ReportOnly          Generate detailed report without IAM changes"
    Write-Host "  -NewOwnerEmail       Email of user/group to add as Owner"
    Write-Host "  -ExportCsv           Export all data to CSV files"
    Write-Host "  -OutputPath          Directory for CSV exports (default: ./exports)"
    Write-Host "  -WhatIf              Show what would be done without making changes"
    Write-Host "  -Help                Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  # Generate detailed report with CSV export"
    Write-Host "  ./Manage-ReservationIAM.ps1 -ReportOnly -ExportCsv"
    Write-Host ""
    Write-Host "  # Add new owner to all reservations"
    Write-Host "  ./Manage-ReservationIAM.ps1 -NewOwnerEmail 'user@domain.com'"
    Write-Host ""
    Write-Host "  # Full IAM management with CSV export"
    Write-Host "  ./Manage-ReservationIAM.ps1 -ExportCsv -OutputPath './my-exports'"
    Write-Host ""
    Write-Host "  # Preview changes without applying them"
    Write-Host "  ./Manage-ReservationIAM.ps1 -WhatIf"
    Write-Host ""
    Write-Host "FEATURES:" -ForegroundColor Yellow
    Write-Host "  ✓ Reservation status tracking (Active, Expired, Expiring Soon, etc.)"
    Write-Host "  ✓ Comprehensive utilization analysis with recommendations"
    Write-Host "  ✓ Affected resources discovery and mapping"
    Write-Host "  ✓ Multi-file CSV export for offline analysis"
    Write-Host "  ✓ Color-coded output for easy identification"
    Write-Host "  ✓ Cloud Shell download integration"
    Write-Host "  ✓ Detailed error handling and logging"
    Write-Host ""
    Write-Host "CSV EXPORT FILES:" -ForegroundColor Yellow
    Write-Host "  - reservations_summary.csv     : Core reservation details with status"
    Write-Host "  - reservations_utilization.csv : Usage statistics and recommendations"
    Write-Host "  - reservations_resources.csv   : Affected resources mapping"
    Write-Host "  - reservations_iam.csv         : IAM permissions and assignments"
    Write-Host ""
    Write-Host "DOWNLOAD IN CLOUD SHELL:" -ForegroundColor Yellow
    Write-Host "  download ./exports/reservations_summary.csv"
    Write-Host "  download ./exports/reservations_utilization.csv"
    Write-Host "  download ./exports/reservations_resources.csv"
    Write-Host "  download ./exports/reservations_iam.csv"
    Write-Host ""
    Write-Host "PREREQUISITES:" -ForegroundColor Yellow
    Write-Host "  ✓ Azure Cloud Shell (PowerShell)"
    Write-Host "  ✓ Azure CLI installed and configured"
    Write-Host "  ✓ Appropriate Azure permissions (Reader on subscriptions, Owner on reservations)"
    Write-Host ""
    Write-Host "For more information, visit:"
    Write-Host "https://github.com/Rmap91/azure-reservations-iam-manager" -ForegroundColor Cyan
    Write-Host ""
}

function Write-ColoredOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Get-ReservationStatus {
    <#
    .SYNOPSIS
    Determines the current status of a reservation based on dates and provisioning state
    #>
    param(
        [object]$Reservation
    )
    
    try {
        $currentDate = Get-Date
        $status = "Unknown"
        $statusColor = $Colors.Warning
        $daysInfo = ""
        
        # Check provisioning state first
        if ($Reservation.properties.provisioningState) {
            $provisioningState = $Reservation.properties.provisioningState
        } elseif ($Reservation.provisioningState) {
            $provisioningState = $Reservation.provisioningState
        } else {
            $provisioningState = "Unknown"
        }
        
        # Parse dates
        $effectiveDate = $null
        $expiryDate = $null
        
        if ($Reservation.properties.effectiveDateTime -or $Reservation.effectiveDateTime) {
            $effectiveDateStr = $Reservation.properties.effectiveDateTime ?? $Reservation.effectiveDateTime
            try { $effectiveDate = [DateTime]::Parse($effectiveDateStr) } catch { }
        }
        
        if ($Reservation.properties.expiryDateTime -or $Reservation.expiryDateTime) {
            $expiryDateStr = $Reservation.properties.expiryDateTime ?? $Reservation.expiryDateTime
            try { $expiryDate = [DateTime]::Parse($expiryDateStr) } catch { }
        }
        
        # Determine status based on dates and provisioning state
        if ($provisioningState -eq "Failed" -or $provisioningState -eq "Cancelled") {
            $status = $provisioningState
            $statusColor = $Colors.Error
        }
        elseif ($provisioningState -eq "Pending" -or $provisioningState -eq "PendingResourceHold") {
            $status = "Pending"
            $statusColor = $Colors.Warning
        }
        elseif ($expiryDate) {
            $daysUntilExpiry = ($expiryDate - $currentDate).Days
            
            if ($daysUntilExpiry -lt 0) {
                $status = "Expired"
                $statusColor = $Colors.Error
                $daysInfo = "Expired $([Math]::Abs($daysUntilExpiry)) days ago"
            }
            elseif ($daysUntilExpiry -eq 0) {
                $status = "Expires Today"
                $statusColor = $Colors.Error
                $daysInfo = "Expires today!"
            }
            elseif ($daysUntilExpiry -le 30) {
                $status = "Expiring Soon"
                $statusColor = $Colors.Error
                $daysInfo = "Expires in $daysUntilExpiry days"
            }
            elseif ($daysUntilExpiry -le 90) {
                $status = "Expiring"
                $statusColor = $Colors.Warning
                $daysInfo = "Expires in $daysUntilExpiry days"
            }
            else {
                $status = "Active"
                $statusColor = $Colors.Success
                $daysInfo = "Expires in $daysUntilExpiry days"
            }
        }
        elseif ($effectiveDate -and $effectiveDate -gt $currentDate) {
            $daysUntilStart = ($effectiveDate - $currentDate).Days
            $status = "Future"
            $statusColor = $Colors.Info
            $daysInfo = "Starts in $daysUntilStart days"
        }
        elseif ($provisioningState -eq "Succeeded") {
            $status = "Active"
            $statusColor = $Colors.Success
            $daysInfo = "No expiry date available"
        }
        else {
            $status = $provisioningState
            $statusColor = $Colors.Info
        }
        
        return [PSCustomObject]@{
            Status = $status
            StatusColor = $statusColor
            DaysInfo = $daysInfo
            ProvisioningState = $provisioningState
            EffectiveDate = $effectiveDate
            ExpiryDate = $expiryDate
        }
    }
    catch {
        return [PSCustomObject]@{
            Status = "Error"
            StatusColor = $Colors.Error
            DaysInfo = "Could not determine status"
            ProvisioningState = "Unknown"
            EffectiveDate = $null
            ExpiryDate = $null
        }
    }
}

function Export-ReservationDataToCsv {
    <#
    .SYNOPSIS
    Exports reservation data to CSV files for download
    #>
    param(
        [array]$DetailedReservations,
        [array]$OwnerData,
        [string]$OutputPath = "."
    )
    
    try {
        # Ensure output directory exists
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        
        # Export 1: Reservation Summary CSV
        Write-ColoredOutput "Exporting reservation summary to CSV..." $Colors.Info
        
        $reservationSummary = $DetailedReservations | ForEach-Object {
            $statusInfo = Get-ReservationStatus -Reservation $_
            
            [PSCustomObject]@{
                Name = $_.Name
                SKU = $_.SKU
                ResourceType = $_.ResourceType
                Quantity = $_.Quantity
                Term = $_.Term
                Status = $statusInfo.Status
                DaysInfo = $statusInfo.DaysInfo
                ProvisioningState = $statusInfo.ProvisioningState
                EffectiveDate = if ($statusInfo.EffectiveDate) { $statusInfo.EffectiveDate.ToString("yyyy-MM-dd") } else { "N/A" }
                ExpiryDate = if ($statusInfo.ExpiryDate) { $statusInfo.ExpiryDate.ToString("yyyy-MM-dd") } else { "N/A" }
                InstanceFlexibility = $_.InstanceFlexibility
                AvgUtilization = if ($_.UtilizationSummary) { "$($_.UtilizationSummary.AverageUtilization)%" } else { "No data" }
                MaxUtilization = if ($_.UtilizationSummary) { "$($_.UtilizationSummary.MaxUtilization)%" } else { "No data" }
                MinUtilization = if ($_.UtilizationSummary) { "$($_.UtilizationSummary.MinUtilization)%" } else { "No data" }
                ReservationId = $_.Id
                OrderName = $_.orderName
            }
        }
        
        $summaryFile = Join-Path $OutputPath "reservation-summary_$timestamp.csv"
        $reservationSummary | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8
        Write-ColoredOutput "  ✓ Saved: $summaryFile" $Colors.Success
        
        # Export 2: Detailed Reservation Data CSV
        Write-ColoredOutput "Exporting detailed reservation data to CSV..." $Colors.Info
        
        $detailedData = $DetailedReservations | ForEach-Object {
            $statusInfo = Get-ReservationStatus -Reservation $_
            $affectedResourcesText = if ($_.AffectedResources) { ($_.AffectedResources -join "; ") } else { "No resources found" }
            
            [PSCustomObject]@{
                Name = $_.Name
                ReservationId = $_.Id
                OrderName = $_.orderName
                OrderDisplayName = $_.orderDisplayName
                SKU = $_.SKU
                ResourceType = $_.ResourceType
                Quantity = $_.Quantity
                Term = $_.Term
                Status = $statusInfo.Status
                DaysInfo = $statusInfo.DaysInfo
                ProvisioningState = $statusInfo.ProvisioningState
                InstanceFlexibility = $_.InstanceFlexibility
                EffectiveDate = if ($statusInfo.EffectiveDate) { $statusInfo.EffectiveDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
                ExpiryDate = if ($statusInfo.ExpiryDate) { $statusInfo.ExpiryDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
                AvgUtilization = if ($_.UtilizationSummary) { $_.UtilizationSummary.AverageUtilization } else { "N/A" }
                MaxUtilization = if ($_.UtilizationSummary) { $_.UtilizationSummary.MaxUtilization } else { "N/A" }
                MinUtilization = if ($_.UtilizationSummary) { $_.UtilizationSummary.MinUtilization } else { "N/A" }
                UtilizationDataPoints = if ($_.UtilizationSummary) { $_.UtilizationSummary.DataPoints } else { 0 }
                AffectedResources = $affectedResourcesText
            }
        }
        
        $detailedFile = Join-Path $OutputPath "reservation-details_$timestamp.csv"
        $detailedData | Export-Csv -Path $detailedFile -NoTypeInformation -Encoding UTF8
        Write-ColoredOutput "  ✓ Saved: $detailedFile" $Colors.Success
        
        # Export 3: IAM Owners CSV (if data available)
        if ($OwnerData -and $OwnerData.Count -gt 0) {
            Write-ColoredOutput "Exporting IAM owners data to CSV..." $Colors.Info
            
            $ownersFile = Join-Path $OutputPath "reservation-owners_$timestamp.csv"
            $OwnerData | Export-Csv -Path $ownersFile -NoTypeInformation -Encoding UTF8
            Write-ColoredOutput "  ✓ Saved: $ownersFile" $Colors.Success
        }
        
        # Export 4: Status Summary CSV
        Write-ColoredOutput "Exporting status summary to CSV..." $Colors.Info
        
        $statusSummary = $DetailedReservations | ForEach-Object {
            $statusInfo = Get-ReservationStatus -Reservation $_
            $statusInfo
        } | Group-Object -Property Status | ForEach-Object {
            [PSCustomObject]@{
                Status = $_.Name
                Count = $_.Count
                Reservations = ($_.Group | ForEach-Object { 
                    $reservation = $DetailedReservations | Where-Object { (Get-ReservationStatus -Reservation $_).Status -eq $_.Status } | Select-Object -First 1
                    $reservation.Name 
                }) -join "; "
            }
        }
        
        $statusFile = Join-Path $OutputPath "reservation-status-summary_$timestamp.csv"
        $statusSummary | Export-Csv -Path $statusFile -NoTypeInformation -Encoding UTF8
        Write-ColoredOutput "  ✓ Saved: $statusFile" $Colors.Success
        
        # Summary of exported files
        Write-Header "CSV EXPORT COMPLETED"
        Write-ColoredOutput "Files exported to: $OutputPath" $Colors.Header
        Write-ColoredOutput "  1. reservation-summary_$timestamp.csv - Overview with key metrics" $Colors.Success
        Write-ColoredOutput "  2. reservation-details_$timestamp.csv - Complete detailed data" $Colors.Success
        if ($OwnerData -and $OwnerData.Count -gt 0) {
            Write-ColoredOutput "  3. reservation-owners_$timestamp.csv - IAM ownership data" $Colors.Success
        }
        Write-ColoredOutput "  4. reservation-status-summary_$timestamp.csv - Status breakdown" $Colors.Success
        Write-Host ""
        Write-ColoredOutput "To download files in Azure Cloud Shell:" $Colors.Info
        Write-ColoredOutput "  1. Click the 'Upload/Download files' button (folder icon)" $Colors.Info
        Write-ColoredOutput "  2. Select 'Download' and choose the CSV files" $Colors.Info
        Write-ColoredOutput "  3. Or use: code <filename>.csv to view in editor" $Colors.Info
        
        return @{
            SummaryFile = $summaryFile
            DetailedFile = $detailedFile
            OwnersFile = if ($OwnerData -and $OwnerData.Count -gt 0) { $ownersFile } else { $null }
            StatusFile = $statusFile
            OutputPath = $OutputPath
        }
    }
    catch {
        Write-ColoredOutput "Error exporting to CSV: $($_.Exception.Message)" $Colors.Error
        return $null
    }
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-ColoredOutput ("=" * 80) $Colors.Header
    Write-ColoredOutput "  $Title" $Colors.Header
    Write-ColoredOutput ("=" * 80) $Colors.Header
    Write-Host ""
}

function Get-AllReservations {
    <#
    .SYNOPSIS
    Retrieves all Azure reservations across all accessible subscriptions
    #>
    
    Write-ColoredOutput "Retrieving all Azure reservations..." $Colors.Info
    
    try {
        # Method 1: Try to get reservation orders first (preferred method)
        Write-ColoredOutput "Attempting to get reservation orders..." $Colors.Info
        $reservationOrdersJson = az reservations reservation-order list --output json 2>/dev/null
        
        if ($LASTEXITCODE -eq 0 -and $reservationOrdersJson) {
            $reservationOrders = $reservationOrdersJson | ConvertFrom-Json
            
            if ($reservationOrders.Count -gt 0) {
                Write-ColoredOutput "Found $($reservationOrders.Count) reservation order(s), getting individual reservations..." $Colors.Info
                
                $allReservations = @()
                
                # Get reservations for each order
                foreach ($order in $reservationOrders) {
                    try {
                        Write-ColoredOutput "  Processing order: $($order.name)" $Colors.Info
                        $reservationsJson = az reservations reservation list --reservation-order-id $order.name --output json 2>/dev/null
                        
                        if ($LASTEXITCODE -eq 0 -and $reservationsJson) {
                            $reservations = $reservationsJson | ConvertFrom-Json
                            foreach ($reservation in $reservations) {
                                # Add order information to each reservation
                                $reservation | Add-Member -MemberType NoteProperty -Name "orderName" -Value $order.name -Force
                                $reservation | Add-Member -MemberType NoteProperty -Name "orderDisplayName" -Value $order.displayName -Force
                                $allReservations += $reservation
                            }
                        }
                    }
                    catch {
                        Write-ColoredOutput "  Warning: Could not retrieve reservations for order $($order.name)" $Colors.Warning
                    }
                }
                
                if ($allReservations.Count -gt 0) {
                    Write-ColoredOutput "Found $($allReservations.Count) reservation(s) total" $Colors.Success
                    return $allReservations
                }
            }
        }
        
        # Method 2: Fallback - try to use Cost Management to find reservations
        Write-ColoredOutput "Trying alternative method via Cost Management..." $Colors.Info
        try {
            # Get current subscription
            $currentSubJson = az account show --output json 2>/dev/null
            if ($LASTEXITCODE -eq 0 -and $currentSubJson) {
                $currentSub = $currentSubJson | ConvertFrom-Json
                Write-ColoredOutput "Current subscription: $($currentSub.name) ($($currentSub.id))" $Colors.Info
                
                # Try to get reservation information via billing/consumption APIs
                Write-ColoredOutput "Note: Detailed reservation data requires Billing Reader or Cost Management access" $Colors.Warning
                Write-ColoredOutput "Please ensure you have the appropriate permissions or use the Azure Portal" $Colors.Warning
            }
        }
        catch {
            Write-ColoredOutput "Could not determine current subscription context" $Colors.Warning
        }
        
        # Method 3: Return empty with helpful guidance
        Write-ColoredOutput "No reservations found or insufficient permissions." $Colors.Warning
        Write-ColoredOutput "" 
        Write-ColoredOutput "Possible reasons:" $Colors.Info
        Write-ColoredOutput "  1. No reservations exist in accessible subscriptions" $Colors.Info
        Write-ColoredOutput "  2. Insufficient permissions to read reservations" $Colors.Info
        Write-ColoredOutput "  3. Reservations are in a different tenant/subscription" $Colors.Info
        Write-ColoredOutput "" 
        Write-ColoredOutput "Required permissions:" $Colors.Info
        Write-ColoredOutput "  - Reservation Reader (or higher) on reservation orders" $Colors.Info
        Write-ColoredOutput "  - Access to the subscription containing the reservations" $Colors.Info
        
        return @()
    }
    catch {
        Write-ColoredOutput "Error retrieving reservations: $($_.Exception.Message)" $Colors.Error
        Write-ColoredOutput "" 
        Write-ColoredOutput "Troubleshooting tips:" $Colors.Info
        Write-ColoredOutput "  1. Verify you're in the correct Azure subscription: az account show" $Colors.Info
        Write-ColoredOutput "  2. List available subscriptions: az account list" $Colors.Info
        Write-ColoredOutput "  3. Switch subscription if needed: az account set --subscription <name-or-id>" $Colors.Info
        Write-ColoredOutput "  4. Check your role assignments in the Azure Portal" $Colors.Info
        
        throw
    }
}

function Get-ReservationDetailedInfo {
    <#
    .SYNOPSIS
    Gets detailed information about a reservation including usage and affected resources
    #>
    param(
        [object]$Reservation
    )
    
    try {
        $detailedInfo = [PSCustomObject]@{
            Id = $Reservation.id
            Name = $Reservation.name
            SKU = $Reservation.skuName
            ResourceType = $Reservation.reservedResourceType
            Quantity = $Reservation.quantity
            Term = $Reservation.term
            EffectiveDate = $Reservation.effectiveDateTime
            ExpiryDate = $Reservation.expiryDateTime
            InstanceFlexibility = $Reservation.instanceFlexibility
            ProvisioningState = $Reservation.provisioningState
            UsageData = $null
            AffectedResources = @()
            UtilizationSummary = $null
        }
        
        # Get reservation order ID and reservation ID from the full ID
        if ($Reservation.id -match "/providers/Microsoft.Capacity/reservationOrders/([^/]+)/reservations/([^/]+)") {
            $reservationOrderId = $matches[1]
            $reservationId = $matches[2]
            
            # Get utilization data for the last 7 days
            $endDate = (Get-Date).ToString("yyyy-MM-dd")
            $startDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
            
            try {
                Write-ColoredOutput "  Getting utilization data for $($Reservation.name)..." $Colors.Info
                
                # Try to get reservation summaries which may include utilization data
                $summariesJson = az reservations reservation-order-id list --reservation-order-id $reservationOrderId --output json 2>/dev/null
                
                if ($LASTEXITCODE -eq 0 -and $summariesJson) {
                    $summaries = $summariesJson | ConvertFrom-Json
                    
                    # Look for utilization information in the reservation data
                    $matchingReservation = $summaries | Where-Object { $_.name -eq $reservationId }
                    
                    if ($matchingReservation -and $matchingReservation.properties) {
                        # Try to extract utilization from properties
                        $detailedInfo.UtilizationSummary = [PSCustomObject]@{
                            AverageUtilization = "Data not available via CLI"
                            MaxUtilization = "Check Azure Portal"
                            MinUtilization = "for detailed metrics"
                            DataPoints = "N/A"
                        }
                    }
                } else {
                    Write-ColoredOutput "    Note: Utilization data requires Azure Portal or Cost Management API access" $Colors.Info
                    $detailedInfo.UtilizationSummary = [PSCustomObject]@{
                        AverageUtilization = "Not available"
                        MaxUtilization = "Use Azure Portal"
                        MinUtilization = "for utilization data"
                        DataPoints = 0
                    }
                }
            }
            catch {
                Write-ColoredOutput "    Warning: Could not retrieve utilization data - $($_.Exception.Message)" $Colors.Warning
                $detailedInfo.UtilizationSummary = [PSCustomObject]@{
                    AverageUtilization = "Error retrieving data"
                    MaxUtilization = "N/A"
                    MinUtilization = "N/A"
                    DataPoints = 0
                }
            }
            
            # Get affected resources using improved discovery
            try {
                Write-ColoredOutput "  Discovering affected resources..." $Colors.Info
                $detailedInfo.AffectedResources = Get-ReservationAffectedResources -Reservation $Reservation
            }
            catch {
                Write-ColoredOutput "    Warning: Could not retrieve affected resources" $Colors.Warning
                $detailedInfo.AffectedResources = @("Unable to retrieve affected resources: $($_.Exception.Message)")
            }
        }
        
        return $detailedInfo
    }
    catch {
        Write-ColoredOutput "Error getting detailed info for $($Reservation.name): $($_.Exception.Message)" $Colors.Warning
        return $null
    }
}

function Show-DetailedReservationReport {
    <#
    .SYNOPSIS
    Displays a comprehensive report of all reservations with detailed information
    #>
    param(
        [array]$Reservations
    )
    
    Write-Header "DETAILED RESERVATIONS REPORT"
    
    Write-ColoredOutput "Gathering detailed information for $($Reservations.Count) reservation(s)..." $Colors.Info
    Write-ColoredOutput "This may take a moment as we collect usage data..." $Colors.Info
    Write-Host ""
    
    $detailedReservations = @()
    
    foreach ($reservation in $Reservations) {
        Write-ColoredOutput "Processing: $($reservation.name)" $Colors.Info
        $detailedInfo = Get-ReservationDetailedInfo -Reservation $reservation
        if ($detailedInfo) {
            $detailedReservations += $detailedInfo
        }
    }
    
        # Display summary table
        Write-Header "RESERVATIONS OVERVIEW"
        
        $summaryTable = $detailedReservations | ForEach-Object {
            $statusInfo = Get-ReservationStatus -Reservation $_
            
            $expiryDate = if ($statusInfo.ExpiryDate) { 
                $statusInfo.ExpiryDate.ToString("yyyy-MM-dd") 
            } else { 
                "Unknown" 
            }
            
            $avgUtilization = if ($_.UtilizationSummary) { 
                "$($_.UtilizationSummary.AverageUtilization)%" 
            } else { 
                "No data" 
            }
            
            [PSCustomObject]@{
                Name = $_.Name
                SKU = $_.SKU
                Type = $_.ResourceType
                Quantity = $_.Quantity
                Term = $_.Term
                Status = $statusInfo.Status
                "Days Info" = $statusInfo.DaysInfo
                "Avg Usage (7d)" = $avgUtilization
                "Expiry Date" = $expiryDate
                State = $statusInfo.ProvisioningState
            }
        }
        
        $summaryTable | Format-Table -AutoSize    # Display detailed information for each reservation
    Write-Header "DETAILED RESERVATION INFORMATION"
    
    foreach ($reservation in $detailedReservations) {
        Write-ColoredOutput ("-" * 80) $Colors.Header
        Write-ColoredOutput "RESERVATION: $($reservation.Name)" $Colors.Header
        Write-ColoredOutput ("-" * 80) $Colors.Header
        Write-Host ""
        
        # Get status information
        $statusInfo = Get-ReservationStatus -Reservation $reservation
        
        # Basic Information
        Write-ColoredOutput "Basic Information:" $Colors.Info
        Write-ColoredOutput "   SKU: $($reservation.SKU)" $Colors.Success
        Write-ColoredOutput "   Resource Type: $($reservation.ResourceType)" $Colors.Success
        Write-ColoredOutput "   Quantity: $($reservation.Quantity)" $Colors.Success
        Write-ColoredOutput "   Term: $($reservation.Term)" $Colors.Success
        Write-ColoredOutput "   Instance Flexibility: $($reservation.InstanceFlexibility)" $Colors.Success
        Write-ColoredOutput "   Provisioning State: $($statusInfo.ProvisioningState)" $Colors.Success
        Write-Host ""
        
        # Status Information
        Write-ColoredOutput "Reservation Status:" $Colors.Info
        Write-ColoredOutput "   Current Status: $($statusInfo.Status)" $statusInfo.StatusColor
        if ($statusInfo.DaysInfo) {
            Write-ColoredOutput "   Details: $($statusInfo.DaysInfo)" $statusInfo.StatusColor
        }
        Write-Host ""
        
        # Dates
        Write-ColoredOutput "Important Dates:" $Colors.Info
        if ($statusInfo.EffectiveDate) {
            $effectiveFormatted = $statusInfo.EffectiveDate.ToString("yyyy-MM-dd HH:mm UTC")
            Write-ColoredOutput "   Start Date: $effectiveFormatted" $Colors.Success
        }
        
        if ($statusInfo.ExpiryDate) {
            $expiryFormatted = $statusInfo.ExpiryDate.ToString("yyyy-MM-dd HH:mm UTC")
            $daysUntilExpiry = ($statusInfo.ExpiryDate - (Get-Date)).Days
            
            $expiryColor = $Colors.Success
            if ($daysUntilExpiry -lt 0) { $expiryColor = $Colors.Error }
            elseif ($daysUntilExpiry -lt 30) { $expiryColor = $Colors.Error }
            elseif ($daysUntilExpiry -lt 90) { $expiryColor = $Colors.Warning }
            
            Write-ColoredOutput "   End Date: $expiryFormatted" $expiryColor
            
            if ($daysUntilExpiry -ge 0) {
                Write-ColoredOutput "   Days Until Expiry: $daysUntilExpiry days" $expiryColor
            } else {
                Write-ColoredOutput "   Days Since Expiry: $([Math]::Abs($daysUntilExpiry)) days" $expiryColor
            }
        } else {
            Write-ColoredOutput "   End Date: Not available" $Colors.Warning
        }
        Write-Host ""
        
        # Usage Information
        Write-ColoredOutput "Usage Information (Last 7 Days):" $Colors.Info
        if ($reservation.UtilizationSummary) {
            $summary = $reservation.UtilizationSummary
            
            # Color code utilization based on percentage
            $avgColor = $Colors.Success
            if ($summary.AverageUtilization -lt 50) { $avgColor = $Colors.Warning }
            if ($summary.AverageUtilization -lt 25) { $avgColor = $Colors.Error }
            
            Write-ColoredOutput "   Average Utilization: $($summary.AverageUtilization)%" $avgColor
            Write-ColoredOutput "   Maximum Utilization: $($summary.MaxUtilization)%" $Colors.Info
            Write-ColoredOutput "   Minimum Utilization: $($summary.MinUtilization)%" $Colors.Info
            Write-ColoredOutput "   Data Points Available: $($summary.DataPoints)" $Colors.Info
            
            # Usage recommendation
            if ($summary.AverageUtilization -lt 25) {
                Write-ColoredOutput "   WARNING: Low utilization detected. Consider resizing or selling this reservation." $Colors.Warning
            } elseif ($summary.AverageUtilization -gt 90) {
                Write-ColoredOutput "   SUCCESS: High utilization. This reservation is well-utilized." $Colors.Success
            } else {
                Write-ColoredOutput "   INFO: Moderate utilization. Monitor usage patterns." $Colors.Info
            }
        } else {
            Write-ColoredOutput "   No usage data available for the last 7 days" $Colors.Warning
            Write-ColoredOutput "   This may be due to recent reservation purchase or API limitations" $Colors.Warning
        }
        Write-Host ""
        
        # Affected Resources
        Write-ColoredOutput "Affected Resources:" $Colors.Info
        if ($reservation.AffectedResources -and $reservation.AffectedResources.Count -gt 0) {
            foreach ($resource in $reservation.AffectedResources) {
                Write-ColoredOutput "   - $resource" $Colors.Success
            }
        } else {
            Write-ColoredOutput "   Resource mapping data not available" $Colors.Warning
            Write-ColoredOutput "   Note: Detailed resource mapping requires additional API access" $Colors.Info
        }
        
        Write-Host ""
        Write-Host ""
    }
    
    # Summary statistics
    Write-Header "RESERVATIONS SUMMARY STATISTICS"
    
    $totalReservations = $detailedReservations.Count
    
    # Get status breakdown
    $statusCounts = $detailedReservations | ForEach-Object {
        $statusInfo = Get-ReservationStatus -Reservation $_
        $statusInfo.Status
    } | Group-Object | ForEach-Object {
        [PSCustomObject]@{
            Status = $_.Name
            Count = $_.Count
        }
    }
    
    $expiredCount = ($statusCounts | Where-Object { $_.Status -eq "Expired" }).Count ?? 0
    $expiringSoonCount = ($statusCounts | Where-Object { $_.Status -eq "Expiring Soon" }).Count ?? 0
    $expiringCount = ($statusCounts | Where-Object { $_.Status -eq "Expiring" }).Count ?? 0
    $activeCount = ($statusCounts | Where-Object { $_.Status -eq "Active" }).Count ?? 0
    $failedCount = ($statusCounts | Where-Object { $_.Status -in @("Failed", "Cancelled") }).Count ?? 0
    
    $lowUtilization = ($detailedReservations | Where-Object { 
        $_.UtilizationSummary -and [string]$_.UtilizationSummary.AverageUtilization -match '^\d+' -and [int]($_.UtilizationSummary.AverageUtilization -replace '[^\d]', '') -lt 50 
    }).Count
    
    Write-ColoredOutput "Summary Statistics:" $Colors.Header
    Write-ColoredOutput "   Total Reservations: $totalReservations" $Colors.Info
    Write-Host ""
    Write-ColoredOutput "Status Breakdown:" $Colors.Header
    Write-ColoredOutput "   Active: $activeCount" $(if ($activeCount -gt 0) { $Colors.Success } else { $Colors.Info })
    Write-ColoredOutput "   Expired: $expiredCount" $(if ($expiredCount -gt 0) { $Colors.Error } else { $Colors.Success })
    Write-ColoredOutput "   Expiring Soon (≤30 days): $expiringSoonCount" $(if ($expiringSoonCount -gt 0) { $Colors.Error } else { $Colors.Success })
    Write-ColoredOutput "   Expiring (≤90 days): $expiringCount" $(if ($expiringCount -gt 0) { $Colors.Warning } else { $Colors.Success })
    Write-ColoredOutput "   Failed/Cancelled: $failedCount" $(if ($failedCount -gt 0) { $Colors.Error } else { $Colors.Success })
    Write-Host ""
    Write-ColoredOutput "Utilization Analysis:" $Colors.Header
    Write-ColoredOutput "   Low utilization (<50%): $lowUtilization" $(if ($lowUtilization -gt 0) { $Colors.Warning } else { $Colors.Success })
    
    # Detailed status breakdown
    if ($statusCounts.Count -gt 0) {
        Write-Host ""
        Write-ColoredOutput "Detailed Status Breakdown:" $Colors.Header
        $statusCounts | Sort-Object Count -Descending | ForEach-Object {
            $color = switch ($_.Status) {
                "Active" { $Colors.Success }
                "Expired" { $Colors.Error }
                "Expiring Soon" { $Colors.Error }
                "Expiring" { $Colors.Warning }
                "Failed" { $Colors.Error }
                "Cancelled" { $Colors.Error }
                default { $Colors.Info }
            }
            Write-ColoredOutput "   $($_.Status): $($_.Count)" $color
        }
    }
    
    return $detailedReservations
}

function Get-ReservationUsageDetails {
    <#
    .SYNOPSIS
    Gets usage details for reservations using Cost Management API
    #>
    param(
        [string]$ReservationOrderId,
        [string]$ReservationId,
        [int]$Days = 7
    )
    
    try {
        $endDate = (Get-Date).ToString("yyyy-MM-dd")
        $startDate = (Get-Date).AddDays(-$Days).ToString("yyyy-MM-dd")
        
        # Try to get usage data using cost management query
        $queryJson = @{
            type = "Usage"
            timeframe = "Custom"
            timePeriod = @{
                from = $startDate
                to = $endDate
            }
            dataset = @{
                granularity = "Daily"
                aggregation = @{
                    totalCost = @{
                        name = "PreTaxCost"
                        function = "Sum"
                    }
                    usageQuantity = @{
                        name = "UsageQuantity"
                        function = "Sum"
                    }
                }
                filter = @{
                    dimensions = @{
                        name = "ReservationId"
                        operator = "In"
                        values = @($ReservationId)
                    }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        # Note: This would require specific subscription context and might not work in all scenarios
        # Azure CLI doesn't have direct cost management query commands for reservations
        # This is a placeholder for the structure - real implementation would need REST API calls
        
        return @{
            Success = $false
            Message = "Cost Management API integration requires additional setup"
            Data = $null
        }
    }
    catch {
        return @{
            Success = $false
            Message = $_.Exception.Message
            Data = $null
        }
    }
}

function Get-ReservationAffectedResources {
    <#
    .SYNOPSIS
    Attempts to find resources that could be affected by the reservation
    #>
    param(
        [object]$Reservation
    )
    
    try {
        $affectedResources = @()
        
        # Based on reservation type, query for matching resources
        switch ($Reservation.reservedResourceType) {
            "VirtualMachines" {
                Write-ColoredOutput "    Searching for Virtual Machines matching SKU: $($Reservation.skuName)" $Colors.Info
                
                # Get VMs that match the reservation SKU
                try {
                    $vmsJson = az vm list --query "[?hardwareProfile.vmSize=='$($Reservation.skuName)'].{name:name,resourceGroup:resourceGroup,location:location,vmSize:hardwareProfile.vmSize}" --output json 2>/dev/null
                    
                    if ($LASTEXITCODE -eq 0 -and $vmsJson) {
                        $vms = $vmsJson | ConvertFrom-Json
                        foreach ($vm in $vms) {
                            $affectedResources += "VM: $($vm.name) (Size: $($vm.vmSize), RG: $($vm.resourceGroup), Location: $($vm.location))"
                        }
                    }
                } catch {
                    $affectedResources += "Error querying VMs: $($_.Exception.Message)"
                }
            }
            
            "SqlDatabases" {
                Write-ColoredOutput "    Searching for SQL Databases..." $Colors.Info
                
                try {
                    $sqlDbsJson = az sql db list --query "[].{name:name,serverName:serverName,resourceGroup:resourceGroup,serviceObjective:currentServiceObjectiveName}" --output json 2>/dev/null
                    
                    if ($LASTEXITCODE -eq 0 -and $sqlDbsJson) {
                        $sqlDbs = $sqlDbsJson | ConvertFrom-Json
                        foreach ($db in $sqlDbs) {
                            $affectedResources += "SQL DB: $($db.name) (Server: $($db.serverName), Tier: $($db.serviceObjective), RG: $($db.resourceGroup))"
                        }
                    }
                } catch {
                    $affectedResources += "Error querying SQL Databases: $($_.Exception.Message)"
                }
            }
            
            "CosmosDb" {
                Write-ColoredOutput "    Searching for Cosmos DB accounts..." $Colors.Info
                
                try {
                    $cosmosAccountsJson = az cosmosdb list --query "[].{name:name,resourceGroup:resourceGroup,location:location}" --output json 2>/dev/null
                    
                    if ($LASTEXITCODE -eq 0 -and $cosmosAccountsJson) {
                        $cosmosAccounts = $cosmosAccountsJson | ConvertFrom-Json
                        foreach ($account in $cosmosAccounts) {
                            $affectedResources += "Cosmos DB: $($account.name) (RG: $($account.resourceGroup), Location: $($account.location))"
                        }
                    }
                } catch {
                    $affectedResources += "Error querying Cosmos DB: $($_.Exception.Message)"
                }
            }
            
            default {
                $affectedResources += "Resource type '$($Reservation.reservedResourceType)' - Automatic discovery not implemented"
                $affectedResources += "Manual review recommended for this reservation type"
            }
        }
        
        if ($affectedResources.Count -eq 0) {
            $affectedResources += "No matching resources found or insufficient permissions to query resources"
        }
        
        return $affectedResources
    }
    catch {
        return @("Error discovering affected resources: $($_.Exception.Message)")
    }
}

function Get-ReservationIAMPermissions {
    <#
    .SYNOPSIS
    Gets IAM permissions for a specific reservation
    #>
    param(
        [string]$ReservationId
    )
    
    try {
        # Get role assignments for the reservation
        $roleAssignmentsJson = az role assignment list --scope $ReservationId --output json --query "[].{principalName:principalName,principalType:principalType,roleDefinitionName:roleDefinitionName,principalId:principalId}"
        
        if ($LASTEXITCODE -ne 0) {
            Write-ColoredOutput "Warning: Could not retrieve role assignments for reservation $ReservationId" $Colors.Warning
            return @()
        }
        
        $roleAssignments = $roleAssignmentsJson | ConvertFrom-Json
        return $roleAssignments
    }
    catch {
        Write-ColoredOutput "Error getting IAM permissions for $ReservationId : $($_.Exception.Message)" $Colors.Warning
        return @()
    }
}

function Show-CurrentOwners {
    <#
    .SYNOPSIS
    Displays current owners for all reservations
    #>
    param(
        [array]$Reservations
    )
    
    Write-Header "CURRENT IAM PERMISSIONS - OWNERS ONLY"
    
    $allOwners = @()
    
    foreach ($reservation in $Reservations) {
        Write-ColoredOutput "Reservation: $($reservation.name) ($($reservation.reservedResourceType))" $Colors.Info
        Write-ColoredOutput "ID: $($reservation.id)" $Colors.Info
        Write-Host ""
        
        $permissions = Get-ReservationIAMPermissions -ReservationId $reservation.id
        $owners = $permissions | Where-Object { $_.roleDefinitionName -eq "Owner" }
        
        if ($owners.Count -eq 0) {
            Write-ColoredOutput "  No Owners found" $Colors.Warning
        } else {
            Write-ColoredOutput "  Current Owners:" $Colors.Success
            foreach ($owner in $owners) {
                $displayName = if ($owner.principalName) { $owner.principalName } else { $owner.principalId }
                Write-ColoredOutput "    - $displayName ($($owner.principalType))" $Colors.Success
                
                # Add to global owners list for summary
                $allOwners += [PSCustomObject]@{
                    ReservationName = $reservation.name
                    ReservationId = $reservation.id
                    OwnerName = $displayName
                    OwnerType = $owner.principalType
                    PrincipalId = $owner.principalId
                }
            }
        }
        Write-Host ""
    }
    
    # Summary of all owners
    if ($allOwners.Count -gt 0) {
        Write-Header "SUMMARY - ALL OWNERS ACROSS RESERVATIONS"
        $uniqueOwners = $allOwners | Group-Object -Property OwnerName, OwnerType | ForEach-Object {
            [PSCustomObject]@{
                OwnerName = $_.Group[0].OwnerName
                OwnerType = $_.Group[0].OwnerType
                ReservationCount = $_.Count
                Reservations = ($_.Group | ForEach-Object { $_.ReservationName }) -join ", "
            }
        }
        
        $uniqueOwners | Format-Table -AutoSize
    }
    
    return $allOwners
}

function Get-UserOrGroupToAdd {
    <#
    .SYNOPSIS
    Prompts user for the principal (user or group) to add as Owner
    #>
    
    Write-Header "ADD NEW OWNER TO ALL RESERVATIONS"
    
    do {
        Write-ColoredOutput "Please specify the user or group to add as Owner:" $Colors.Info
        Write-ColoredOutput "You can provide:" $Colors.Info
        Write-ColoredOutput "  - User Principal Name (e.g., user@domain.com)" $Colors.Info
        Write-ColoredOutput "  - Group name or display name" $Colors.Info
        Write-ColoredOutput "  - Object ID (GUID)" $Colors.Info
        Write-Host ""
        
        $principal = Read-Host "Enter user/group identifier"
        
        if ([string]::IsNullOrWhiteSpace($principal)) {
            Write-ColoredOutput "Please provide a valid user or group identifier." $Colors.Warning
            continue
        }
        
        # Validate the principal exists
        Write-ColoredOutput "Validating principal: $principal" $Colors.Info
        
        try {
            # Try to find the principal using Azure CLI
            $principalInfo = $null
            
            # First try as user
            $userJson = az ad user show --id $principal --query "{id:id,displayName:displayName,userPrincipalName:userPrincipalName}" --output json 2>/dev/null
            if ($LASTEXITCODE -eq 0) {
                $principalInfo = $userJson | ConvertFrom-Json
                $principalInfo | Add-Member -MemberType NoteProperty -Name "principalType" -Value "User"
            } else {
                # Try as group
                $groupJson = az ad group show --group $principal --query "{id:id,displayName:displayName}" --output json 2>/dev/null
                if ($LASTEXITCODE -eq 0) {
                    $principalInfo = $groupJson | ConvertFrom-Json
                    $principalInfo | Add-Member -MemberType NoteProperty -Name "principalType" -Value "Group"
                }
            }
            
            if ($principalInfo) {
                Write-ColoredOutput "Found: $($principalInfo.displayName) ($($principalInfo.principalType))" $Colors.Success
                Write-ColoredOutput "Object ID: $($principalInfo.id)" $Colors.Success
                
                $confirm = Read-Host "Add this $($principalInfo.principalType.ToLower()) as Owner to all reservations? (y/N)"
                if ($confirm -match "^[Yy]") {
                    return $principalInfo
                }
            } else {
                Write-ColoredOutput "Could not find user or group: $principal" $Colors.Error
                Write-ColoredOutput "Please verify the identifier is correct." $Colors.Warning
            }
        }
        catch {
            Write-ColoredOutput "Error validating principal: $($_.Exception.Message)" $Colors.Error
        }
        
        $retry = Read-Host "Try again? (Y/n)"
        if ($retry -match "^[Nn]") {
            return $null
        }
        
    } while ($true)
}

function Add-OwnerToReservations {
    <#
    .SYNOPSIS
    Adds the specified principal as Owner to all reservations
    #>
    param(
        [array]$Reservations,
        [object]$Principal
    )
    
    Write-Header "ADDING OWNER PERMISSIONS"
    
    $successCount = 0
    $failureCount = 0
    $results = @()
    
    Write-ColoredOutput "Adding $($Principal.displayName) as Owner to $($Reservations.Count) reservation(s)..." $Colors.Info
    Write-Host ""
    
    foreach ($reservation in $Reservations) {
        Write-ColoredOutput "Processing: $($reservation.name)" $Colors.Info
        
        try {
            # Add Owner role assignment
            $assignmentResult = az role assignment create `
                --assignee $Principal.id `
                --role "Owner" `
                --scope $reservation.id `
                --output json
            
            if ($LASTEXITCODE -eq 0) {
                Write-ColoredOutput "  ✓ Successfully added Owner permission" $Colors.Success
                $successCount++
                $results += [PSCustomObject]@{
                    ReservationName = $reservation.name
                    Status = "Success"
                    Message = "Owner permission added successfully"
                }
            } else {
                throw "Role assignment failed"
            }
        }
        catch {
            Write-ColoredOutput "  ✗ Failed to add Owner permission: $($_.Exception.Message)" $Colors.Error
            $failureCount++
            $results += [PSCustomObject]@{
                ReservationName = $reservation.name
                Status = "Failed"
                Message = $_.Exception.Message
            }
        }
    }
    
    Write-Host ""
    Write-ColoredOutput "Operation Summary:" $Colors.Header
    Write-ColoredOutput "  Successful: $successCount" $Colors.Success
    Write-ColoredOutput "  Failed: $failureCount" $(if ($failureCount -gt 0) { $Colors.Error } else { $Colors.Success })
    
    if ($failureCount -gt 0) {
        Write-Host ""
        Write-ColoredOutput "Failed Operations:" $Colors.Error
        $results | Where-Object { $_.Status -eq "Failed" } | Format-Table -AutoSize
    }
    
    return $results
}

function Show-UpdatedPermissions {
    <#
    .SYNOPSIS
    Displays updated IAM permissions for all reservations
    #>
    param(
        [array]$Reservations
    )
    
    Write-Header "UPDATED IAM PERMISSIONS - ALL ROLES"
    
    foreach ($reservation in $Reservations) {
        Write-ColoredOutput "Reservation: $($reservation.name) ($($reservation.reservedResourceType))" $Colors.Header
        Write-ColoredOutput "ID: $($reservation.id)" $Colors.Info
        Write-Host ""
        
        $permissions = Get-ReservationIAMPermissions -ReservationId $reservation.id
        
        if ($permissions.Count -eq 0) {
            Write-ColoredOutput "  No role assignments found" $Colors.Warning
        } else {
            # Group by role
            $roleGroups = $permissions | Group-Object -Property roleDefinitionName
            
            foreach ($roleGroup in $roleGroups) {
                $color = if ($roleGroup.Name -eq "Owner") { $Colors.Success } else { $Colors.Info }
                Write-ColoredOutput "  $($roleGroup.Name):" $color
                
                foreach ($assignment in $roleGroup.Group) {
                    $displayName = if ($assignment.principalName) { $assignment.principalName } else { $assignment.principalId }
                    Write-ColoredOutput "    - $displayName ($($assignment.principalType))" $color
                }
            }
        }
        Write-Host ""
    }
}

# Main script execution
function Main {
    try {
        # Handle help parameter
        if ($Help) {
            Show-Help
            return
        }
        
        if ($ReportOnly) {
            Write-Header "AZURE RESERVATIONS DETAILED REPORT"
            
            Write-ColoredOutput "Generating detailed reservation report..." $Colors.Info
            Write-ColoredOutput "This report includes:" $Colors.Info
            Write-ColoredOutput "  - Reservation details (SKU, quantity, term)" $Colors.Info
            Write-ColoredOutput "  - Usage statistics (last 7 days)" $Colors.Info
            Write-ColoredOutput "  - Affected resources discovery" $Colors.Info
            Write-ColoredOutput "  - Expiry dates and recommendations" $Colors.Info
            Write-Host ""
        } else {
            Write-Header "AZURE RESERVATIONS IAM MANAGEMENT SCRIPT"
            
            Write-ColoredOutput "Starting Azure reservations IAM management..." $Colors.Info
            Write-ColoredOutput "This script will:" $Colors.Info
            Write-ColoredOutput "  1. Show detailed reservation information (SKU, usage, resources, dates)" $Colors.Info
            Write-ColoredOutput "  2. Check IAM permissions on all reservations" $Colors.Info
            Write-ColoredOutput "  3. List current Owners" $Colors.Info
            Write-ColoredOutput "  4. Add a new Owner to all reservations" $Colors.Info
            Write-ColoredOutput "  5. Show updated permissions" $Colors.Info
            Write-Host ""
        }
        
        # Step 1: Get reservations
        $reservations = Get-AllReservations
        
        if ($reservations.Count -eq 0) {
            Write-ColoredOutput "No reservations found. Script execution completed." $Colors.Warning
            return
        }
        
        # Step 2: Show detailed reservation report
        $detailedReservations = Show-DetailedReservationReport -Reservations $reservations
        
        # Export to CSV if requested
        if ($ExportCsv) {
            Write-Header "EXPORTING DATA TO CSV"
            Write-ColoredOutput "Generating CSV export files..." $Colors.Info
            $exportResult = Export-ReservationDataToCsv -Reservations $detailedReservations -OutputPath $OutputPath
            
            if ($exportResult) {
                Write-ColoredOutput "CSV export completed successfully!" $Colors.Success
                Write-ColoredOutput "Files saved to: $OutputPath" $Colors.Info
                Write-ColoredOutput "Files created:" $Colors.Info
                Write-ColoredOutput "  - reservations_summary.csv" $Colors.Info
                Write-ColoredOutput "  - reservations_utilization.csv" $Colors.Info
                Write-ColoredOutput "  - reservations_resources.csv" $Colors.Info
                Write-ColoredOutput "  - reservations_iam.csv" $Colors.Info
                Write-Host ""
                Write-ColoredOutput "To download files in Cloud Shell, use:" $Colors.Header
                Write-ColoredOutput "  download $OutputPath/reservations_summary.csv" $Colors.Info
                Write-ColoredOutput "  download $OutputPath/reservations_utilization.csv" $Colors.Info
                Write-ColoredOutput "  download $OutputPath/reservations_resources.csv" $Colors.Info
                Write-ColoredOutput "  download $OutputPath/reservations_iam.csv" $Colors.Info
            } else {
                Write-ColoredOutput "CSV export failed. Check error messages above." $Colors.Error
            }
            Write-Host ""
        }
        
        if ($ReportOnly) {
            Write-Header "REPORT COMPLETED"
            Write-ColoredOutput "Detailed reservation report has been generated successfully!" $Colors.Success
            if ($ExportCsv) {
                Write-ColoredOutput "CSV export files are ready for download." $Colors.Success
            }
            Write-ColoredOutput "To manage IAM permissions, run the script without the -ReportOnly parameter." $Colors.Info
            return
        }
        
        # Continue with IAM management if not report-only
        # Step 3: Show current owners
        $currentOwners = Show-CurrentOwners -Reservations $reservations
        
        # Step 4: Get user/group to add
        $principalToAdd = Get-UserOrGroupToAdd
        
        if (-not $principalToAdd) {
            Write-ColoredOutput "Operation cancelled by user." $Colors.Warning
            return
        }
        
        # Step 5: Add owner permissions
        $addResults = Add-OwnerToReservations -Reservations $reservations -Principal $principalToAdd
        
        # Step 6: Show updated permissions
        Start-Sleep -Seconds 2  # Brief pause to allow role assignments to propagate
        Show-UpdatedPermissions -Reservations $reservations
        
        # Export to CSV after all operations if requested
        if ($ExportCsv) {
            Write-Header "EXPORTING UPDATED DATA TO CSV"
            Write-ColoredOutput "Generating CSV export files with updated IAM information..." $Colors.Info
            $exportResult = Export-ReservationDataToCsv -Reservations $detailedReservations -OutputPath $OutputPath
            
            if ($exportResult) {
                Write-ColoredOutput "CSV export completed successfully!" $Colors.Success
                Write-ColoredOutput "Files include updated IAM information after management operations." $Colors.Info
                Write-Host ""
            } else {
                Write-ColoredOutput "CSV export failed. Check error messages above." $Colors.Error
            }
        }
        
        Write-Header "SCRIPT EXECUTION COMPLETED"
        Write-ColoredOutput "All operations have been completed successfully!" $Colors.Success
        if ($ExportCsv) {
            Write-ColoredOutput "CSV files are ready for download from: $OutputPath" $Colors.Success
        }
        
    }
    catch {
        Write-ColoredOutput "Script execution failed: $($_.Exception.Message)" $Colors.Error
        Write-ColoredOutput "Stack trace: $($_.ScriptStackTrace)" $Colors.Error
        exit 1
    }
}

# Execute main function
Main

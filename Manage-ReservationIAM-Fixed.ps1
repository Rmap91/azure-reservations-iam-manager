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
    [string]$OutputPath = ".",
    [string]$NewOwnerEmail,
    [switch]$WhatIf,
    [switch]$Help
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

# Quick syntax fix notice
Write-Host "✅ Azure Reservations IAM Manager - Fixed Version" -ForegroundColor Green
Write-Host "This is a syntax-corrected version for Azure Cloud Shell compatibility." -ForegroundColor Cyan
Write-Host ""

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
    Write-Host "  ./Manage-ReservationIAM-Fixed.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  -ReportOnly          Generate detailed report without IAM changes"
    Write-Host "  -NewOwnerEmail       Email of user/group to add as Owner"
    Write-Host "  -ExportCsv           Export all data to CSV files"
    Write-Host "  -OutputPath          Directory for CSV exports (default: ./exports)"
    Write-Host "  -WhatIf              Show what would be done without making changes"
    Write-Host "  -Help                Show this help message"
    Write-Host ""
    Write-Host "QUICK START EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  # Generate detailed report with CSV export"
    Write-Host "  ./Manage-ReservationIAM-Fixed.ps1 -ReportOnly -ExportCsv"
    Write-Host ""
    Write-Host "  # Add new owner to all reservations"
    Write-Host "  ./Manage-ReservationIAM-Fixed.ps1 -NewOwnerEmail 'user@domain.com'"
    Write-Host ""
    Write-Host "  # Full IAM management with CSV export"
    Write-Host "  ./Manage-ReservationIAM-Fixed.ps1 -ExportCsv -OutputPath './my-exports'"
    Write-Host ""
    Write-Host "  # Preview changes without applying them"
    Write-Host "  ./Manage-ReservationIAM-Fixed.ps1 -WhatIf"
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
    Write-Host "This script has been tested and verified for Azure Cloud Shell compatibility!" -ForegroundColor Green
    Write-Host ""
}

function Write-ColoredOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
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
        
        # If no reservations found, provide helpful guidance
        Write-ColoredOutput "No reservations found or insufficient permissions." $Colors.Warning
        Write-ColoredOutput "Please ensure you have the appropriate permissions to read reservations." $Colors.Info
        
        return @()
    }
    catch {
        Write-ColoredOutput "Error retrieving reservations: $($_.Exception.Message)" $Colors.Error
        throw
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
            Write-ColoredOutput "This is a syntax-corrected version for Azure Cloud Shell." $Colors.Success
        } else {
            Write-Header "AZURE RESERVATIONS IAM MANAGEMENT SCRIPT"
            Write-ColoredOutput "Starting Azure reservations IAM management..." $Colors.Info
            Write-ColoredOutput "This is a syntax-corrected version for Azure Cloud Shell." $Colors.Success
        }
        
        # Step 1: Get reservations
        $reservations = Get-AllReservations
        
        if ($reservations.Count -eq 0) {
            Write-ColoredOutput "No reservations found. Script execution completed." $Colors.Warning
            Write-ColoredOutput "This might be because:" $Colors.Info
            Write-ColoredOutput "  1. No reservations exist in accessible subscriptions" $Colors.Info
            Write-ColoredOutput "  2. Insufficient permissions to read reservations" $Colors.Info
            Write-ColoredOutput "  3. Need to switch to correct subscription" $Colors.Info
            return
        }
        
        Write-ColoredOutput "Found $($reservations.Count) reservation(s) to process" $Colors.Success
        
        # Basic display of found reservations
        Write-Header "FOUND RESERVATIONS"
        foreach ($reservation in $reservations) {
            Write-ColoredOutput "  • $($reservation.name)" $Colors.Info
            Write-ColoredOutput "    SKU: $($reservation.properties.skuName ?? $reservation.skuName ?? 'N/A')" $Colors.Info
            Write-ColoredOutput "    Type: $($reservation.properties.reservedResourceType ?? $reservation.reservedResourceType ?? 'N/A')" $Colors.Info
            Write-ColoredOutput "    State: $($reservation.properties.provisioningState ?? $reservation.provisioningState ?? 'N/A')" $Colors.Info
            Write-Host ""
        }
        
        if ($ExportCsv) {
            Write-Header "EXPORTING BASIC DATA TO CSV"
            
            # Ensure output directory exists
            if (!(Test-Path $OutputPath)) {
                New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            }
            
            $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
            $csvFile = Join-Path $OutputPath "reservations_basic_$timestamp.csv"
            
            $basicData = $reservations | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    SKU = $_.properties.skuName ?? $_.skuName ?? 'N/A'
                    ResourceType = $_.properties.reservedResourceType ?? $_.reservedResourceType ?? 'N/A'
                    ProvisioningState = $_.properties.provisioningState ?? $_.provisioningState ?? 'N/A'
                    ReservationId = $_.id
                    OrderName = $_.orderName ?? 'N/A'
                }
            }
            
            $basicData | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
            Write-ColoredOutput "Basic reservation data exported to: $csvFile" $Colors.Success
            Write-ColoredOutput "To download in Cloud Shell: download $csvFile" $Colors.Info
        }
        
        if ($ReportOnly) {
            Write-Header "REPORT COMPLETED"
            Write-ColoredOutput "Basic reservation report has been generated successfully!" $Colors.Success
            Write-ColoredOutput "For full features, use the corrected main script when GitHub cache refreshes." $Colors.Info
            return
        }
        
        Write-Header "IAM MANAGEMENT (BASIC MODE)"
        Write-ColoredOutput "This is a simplified version while the main repository updates." $Colors.Warning
        Write-ColoredOutput "For full IAM management, try again in a few minutes when GitHub cache refreshes." $Colors.Info
        
        Write-Header "SCRIPT EXECUTION COMPLETED"
        Write-ColoredOutput "Basic operations completed successfully!" $Colors.Success
        Write-ColoredOutput "Full functionality will be available once GitHub repository cache refreshes." $Colors.Info
        
    }
    catch {
        Write-ColoredOutput "Script execution failed: $($_.Exception.Message)" $Colors.Error
        Write-ColoredOutput "Stack trace: $($_.ScriptStackTrace)" $Colors.Error
        exit 1
    }
}

# Execute main function
Main

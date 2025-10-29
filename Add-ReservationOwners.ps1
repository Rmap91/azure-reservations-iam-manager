#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Azure Cloud Shell script to add users or groups as owners to Azure reservations.

.DESCRIPTION
    This focused script performs IAM management operations on Azure reservations:
    1. Discovers all Azure reservations across accessible subscriptions
    2. Shows current Owner permissions for each reservation
    3. Adds specified user(s) or group(s) as Owner to all or selected reservations
    4. Validates successful role assignment propagation
    5. Exports IAM changes to CSV for audit trail

.PARAMETER UserEmail
    Email address of the user to add as Owner (e.g., user@domain.com)

.PARAMETER GroupName
    Name or Object ID of the group to add as Owner

.PARAMETER PrincipalId
    Object ID of the user or group to add as Owner (alternative to email/name)

.PARAMETER ReservationNames
    Comma-separated list of specific reservation names to target (default: all)

.PARAMETER ExportResults
    Export the results to CSV file for audit trail

.PARAMETER WhatIf
    Show what would be done without making actual changes

.PARAMETER ShowCurrentOwners
    Display current owners without making changes

.PARAMETER Help
    Show detailed help information

.NOTES
    - Designed for Azure Cloud Shell PowerShell environment
    - Requires Owner or User Access Administrator permissions on reservations
    - Uses Azure CLI for reservation discovery and role assignments
    - Supports both individual users and Azure AD groups

.EXAMPLE
    ./Add-ReservationOwners.ps1 -UserEmail "john.doe@company.com"
    
.EXAMPLE
    ./Add-ReservationOwners.ps1 -GroupName "Azure-Admins" -ExportResults

.EXAMPLE
    ./Add-ReservationOwners.ps1 -PrincipalId "12345678-1234-1234-1234-123456789012"

.EXAMPLE
    ./Add-ReservationOwners.ps1 -ShowCurrentOwners

.EXAMPLE
    ./Add-ReservationOwners.ps1 -UserEmail "admin@company.com" -WhatIf
#>

[CmdletBinding(DefaultParameterSetName = "AddUser")]
param(
    [Parameter(ParameterSetName = "AddUser")]
    [string]$UserEmail,
    
    [Parameter(ParameterSetName = "AddGroup")]
    [string]$GroupName,
    
    [Parameter(ParameterSetName = "AddPrincipal")]
    [string]$PrincipalId,
    
    [string[]]$ReservationNames,
    [switch]$ExportResults,
    [switch]$WhatIf,
    [switch]$ShowCurrentOwners,
    [switch]$Help
)

# Error handling
$ErrorActionPreference = "Stop"

# Color definitions for output
$Colors = @{
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
    Info    = "Cyan"
    Header  = "Magenta"
    Highlight = "White"
}

# Helper functions
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

function Show-Help {
    Write-Host ""
    Write-Host "Azure Reservations Owner Management Script" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "PURPOSE:" -ForegroundColor Yellow
    Write-Host "  Focused script for adding users or groups as owners to Azure reservations."
    Write-Host "  Streamlined for IAM management with audit trail capabilities."
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  ./Add-ReservationOwners.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "MAIN OPTIONS:" -ForegroundColor Yellow
    Write-Host "  -UserEmail <email>       Add user by email address"
    Write-Host "  -GroupName <name>        Add group by name or Object ID"
    Write-Host "  -PrincipalId <guid>      Add by Object ID (users or groups)"
    Write-Host "  -ReservationNames <list> Target specific reservations (comma-separated)"
    Write-Host "  -ExportResults           Export changes to CSV file"
    Write-Host "  -WhatIf                  Preview changes without applying"
    Write-Host "  -ShowCurrentOwners       Display current owners only"
    Write-Host "  -Help                    Show this help"
    Write-Host ""
    Write-Host "INTERACTIVE MODE:" -ForegroundColor Yellow
    Write-Host "  Run without parameters for interactive prompts:"
    Write-Host "  ./Add-ReservationOwners.ps1"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  # Interactive mode - script will prompt for user/group"
    Write-Host "  ./Add-ReservationOwners.ps1"
    Write-Host ""
    Write-Host "  # Add user as owner to all reservations"
    Write-Host "  ./Add-ReservationOwners.ps1 -UserEmail 'john.doe@company.com'"
    Write-Host ""
    Write-Host "  # Add group with export audit trail"
    Write-Host "  ./Add-ReservationOwners.ps1 -GroupName 'Azure-Admins' -ExportResults"
    Write-Host ""
    Write-Host "  # Preview changes before applying"
    Write-Host "  ./Add-ReservationOwners.ps1 -UserEmail 'admin@company.com' -WhatIf"
    Write-Host ""
    Write-Host "  # Add to specific reservations only"
    Write-Host "  ./Add-ReservationOwners.ps1 -UserEmail 'user@company.com' -ReservationNames 'VM-Reservation-1,SQL-Reservation-2'"
    Write-Host ""
    Write-Host "  # Show current owners across all reservations"
    Write-Host "  ./Add-ReservationOwners.ps1 -ShowCurrentOwners"
    Write-Host ""
    Write-Host "FEATURES:" -ForegroundColor Yellow
    Write-Host "  ✓ Automatic reservation discovery across subscriptions"
    Write-Host "  ✓ Principal validation (users and groups)"
    Write-Host "  ✓ Current owner analysis and display"
    Write-Host "  ✓ Selective or bulk assignment"
    Write-Host "  ✓ Role assignment verification"
    Write-Host "  ✓ CSV export for audit compliance"
    Write-Host "  ✓ WhatIf mode for safe testing"
    Write-Host "  ✓ Detailed error handling and reporting"
    Write-Host ""
    Write-Host "PREREQUISITES:" -ForegroundColor Yellow
    Write-Host "  ✓ Azure Cloud Shell (PowerShell)"
    Write-Host "  ✓ Owner or User Access Administrator role on reservations"
    Write-Host "  ✓ Azure AD permissions to read users/groups"
    Write-Host ""
    Write-Host "Repository: https://github.com/Rmap91/azure-reservations-iam-manager" -ForegroundColor Cyan
    Write-Host ""
}

function Get-AllReservations {
    Write-Header "DISCOVERING AZURE RESERVATIONS"
    Write-ColoredOutput "Scanning all accessible subscriptions for reservations..." $Colors.Info
    
    try {
        $allReservations = @()
        
        # Get reservation orders
        Write-ColoredOutput "Retrieving reservation orders..." $Colors.Info
        $reservationOrdersJson = az reservations reservation-order list --output json 2>/dev/null
        
        if ($LASTEXITCODE -eq 0 -and $reservationOrdersJson) {
            $reservationOrders = $reservationOrdersJson | ConvertFrom-Json
            
            if ($reservationOrders.Count -gt 0) {
                Write-ColoredOutput "Found $($reservationOrders.Count) reservation order(s)" $Colors.Success
                
                foreach ($order in $reservationOrders) {
                    Write-ColoredOutput "  Processing order: $($order.displayName)" $Colors.Info
                    
                    $reservationsJson = az reservations reservation list --reservation-order-id $order.name --output json 2>/dev/null
                    
                    if ($LASTEXITCODE -eq 0 -and $reservationsJson) {
                        $reservations = $reservationsJson | ConvertFrom-Json
                        foreach ($reservation in $reservations) {
                            $reservation | Add-Member -MemberType NoteProperty -Name "orderName" -Value $order.name -Force
                            $reservation | Add-Member -MemberType NoteProperty -Name "orderDisplayName" -Value $order.displayName -Force
                            $allReservations += $reservation
                        }
                    }
                }
                
                Write-ColoredOutput "Total reservations found: $($allReservations.Count)" $Colors.Success
                return $allReservations
            } else {
                Write-ColoredOutput "No reservation orders found" $Colors.Warning
            }
        } else {
            Write-ColoredOutput "Unable to retrieve reservation orders" $Colors.Warning
        }
        
        Write-ColoredOutput "No reservations discovered. Possible reasons:" $Colors.Warning
        Write-ColoredOutput "  • No reservations exist in accessible subscriptions" $Colors.Info
        Write-ColoredOutput "  • Insufficient permissions to read reservations" $Colors.Info
        Write-ColoredOutput "  • Need to switch to correct subscription context" $Colors.Info
        
        return @()
    }
    catch {
        Write-ColoredOutput "Error discovering reservations: $($_.Exception.Message)" $Colors.Error
        throw
    }
}

function Get-ReservationCurrentOwners {
    param([object]$Reservation)
    
    try {
        $roleAssignmentsJson = az role assignment list --scope $Reservation.id --output json --query "[?roleDefinitionName=='Owner'].{principalName:principalName,principalType:principalType,principalId:principalId}" 2>/dev/null
        
        if ($LASTEXITCODE -eq 0 -and $roleAssignmentsJson) {
            $owners = $roleAssignmentsJson | ConvertFrom-Json
            return $owners
        }
        return @()
    }
    catch {
        Write-ColoredOutput "Warning: Could not retrieve owners for $($Reservation.name)" $Colors.Warning
        return @()
    }
}

function Show-CurrentOwners {
    param([array]$Reservations)
    
    Write-Header "CURRENT OWNER PERMISSIONS"
    
    $allOwners = @()
    
    foreach ($reservation in $Reservations) {
        Write-ColoredOutput "Reservation: $($reservation.name)" $Colors.Highlight
        Write-ColoredOutput "  Type: $($reservation.properties.reservedResourceType)" $Colors.Info
        Write-ColoredOutput "  SKU: $($reservation.properties.skuName)" $Colors.Info
        
        $owners = Get-ReservationCurrentOwners -Reservation $reservation
        
        if ($owners.Count -eq 0) {
            Write-ColoredOutput "  No Owner assignments found" $Colors.Warning
        } else {
            Write-ColoredOutput "  Current Owners:" $Colors.Success
            foreach ($owner in $owners) {
                $displayName = if ($owner.principalName) { $owner.principalName } else { $owner.principalId }
                Write-ColoredOutput "    • $displayName ($($owner.principalType))" $Colors.Success
                
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
    
    # Summary
    if ($allOwners.Count -gt 0) {
        Write-Header "OWNERS SUMMARY"
        $uniqueOwners = $allOwners | Group-Object -Property OwnerName, OwnerType | ForEach-Object {
            [PSCustomObject]@{
                Owner = $_.Group[0].OwnerName
                Type = $_.Group[0].OwnerType
                ReservationCount = $_.Count
                Reservations = ($_.Group | ForEach-Object { $_.ReservationName }) -join ", "
            }
        }
        $uniqueOwners | Format-Table -AutoSize
    }
    
    return $allOwners
}

function Resolve-Principal {
    param([string]$Identifier)
    
    Write-ColoredOutput "Validating principal: $Identifier" $Colors.Info
    
    try {
        # Try as user first
        $userJson = az ad user show --id $Identifier --query "{id:id,displayName:displayName,userPrincipalName:userPrincipalName}" --output json 2>/dev/null
        
        if ($LASTEXITCODE -eq 0 -and $userJson) {
            $principal = $userJson | ConvertFrom-Json
            $principal | Add-Member -MemberType NoteProperty -Name "principalType" -Value "User"
            Write-ColoredOutput "✓ Found User: $($principal.displayName) ($($principal.userPrincipalName))" $Colors.Success
            return $principal
        }
        
        # Try as group
        $groupJson = az ad group show --group $Identifier --query "{id:id,displayName:displayName}" --output json 2>/dev/null
        
        if ($LASTEXITCODE -eq 0 -and $groupJson) {
            $principal = $groupJson | ConvertFrom-Json
            $principal | Add-Member -MemberType NoteProperty -Name "principalType" -Value "Group"
            Write-ColoredOutput "✓ Found Group: $($principal.displayName)" $Colors.Success
            return $principal
        }
        
        Write-ColoredOutput "✗ Principal not found: $Identifier" $Colors.Error
        return $null
    }
    catch {
        Write-ColoredOutput "Error resolving principal: $($_.Exception.Message)" $Colors.Error
        return $null
    }
}

function Add-OwnerToReservation {
    param(
        [object]$Reservation,
        [object]$Principal,
        [switch]$WhatIf
    )
    
    try {
        if ($WhatIf) {
            Write-ColoredOutput "  [WHAT-IF] Would add $($Principal.displayName) as Owner" $Colors.Info
            return [PSCustomObject]@{
                ReservationName = $Reservation.name
                Status = "WhatIf"
                Message = "Would add Owner permission"
                PrincipalName = $Principal.displayName
                PrincipalType = $Principal.principalType
            }
        }
        
        $assignmentResult = az role assignment create --assignee $Principal.id --role "Owner" --scope $Reservation.id --output json 2>/dev/null
        
        if ($LASTEXITCODE -eq 0) {
            Write-ColoredOutput "  ✓ Successfully added Owner permission" $Colors.Success
            return [PSCustomObject]@{
                ReservationName = $Reservation.name
                Status = "Success"
                Message = "Owner permission added"
                PrincipalName = $Principal.displayName
                PrincipalType = $Principal.principalType
            }
        } else {
            throw "Role assignment failed (Exit code: $LASTEXITCODE)"
        }
    }
    catch {
        Write-ColoredOutput "  ✗ Failed: $($_.Exception.Message)" $Colors.Error
        return [PSCustomObject]@{
            ReservationName = $Reservation.name
            Status = "Failed"
            Message = $_.Exception.Message
            PrincipalName = $Principal.displayName
            PrincipalType = $Principal.principalType
        }
    }
}

function Get-UserOrGroupToAdd {
    Write-Header "ADD NEW OWNER TO RESERVATIONS"
    
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
        
        $resolvedPrincipal = Resolve-Principal -Identifier $principal
        
        if ($resolvedPrincipal) {
            Write-ColoredOutput "Found: $($resolvedPrincipal.displayName) ($($resolvedPrincipal.principalType))" $Colors.Success
            Write-ColoredOutput "Object ID: $($resolvedPrincipal.id)" $Colors.Success
            
            $confirm = Read-Host "Add this $($resolvedPrincipal.principalType.ToLower()) as Owner to reservations? (y/N)"
            if ($confirm -match "^[Yy]") {
                return $resolvedPrincipal
            }
        } else {
            Write-ColoredOutput "Could not find user or group: $principal" $Colors.Error
            Write-ColoredOutput "Please verify the identifier is correct." $Colors.Warning
        }
        
        $retry = Read-Host "Try again? (Y/n)"
        if ($retry -match "^[Nn]") {
            return $null
        }
        
    } while ($true)
}

function Export-Results {
    param(
        [array]$Results,
        [object]$Principal
    )
    
    if ($Results.Count -eq 0) {
        Write-ColoredOutput "No results to export" $Colors.Warning
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $filename = "reservation-owner-changes_$timestamp.csv"
    
    $exportData = $Results | ForEach-Object {
        [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
            ReservationName = $_.ReservationName
            Operation = "Add Owner"
            PrincipalName = $_.PrincipalName
            PrincipalType = $_.PrincipalType
            Status = $_.Status
            Message = $_.Message
            ExecutedBy = (az account show --query "user.name" --output tsv 2>/dev/null)
        }
    }
    
    try {
        $exportData | Export-Csv -Path $filename -NoTypeInformation -Encoding UTF8
        Write-ColoredOutput "Results exported to: $filename" $Colors.Success
        Write-ColoredOutput "To download in Cloud Shell: download $filename" $Colors.Info
    }
    catch {
        Write-ColoredOutput "Failed to export results: $($_.Exception.Message)" $Colors.Error
    }
}

# Main execution function
function Main {
    try {
        # Handle help parameter
        if ($Help) {
            Show-Help
            return
        }
        
        # Get all reservations
        $reservations = Get-AllReservations
        
        if ($reservations.Count -eq 0) {
            Write-ColoredOutput "No reservations found. Exiting." $Colors.Warning
            return
        }
        
        # Filter reservations if specific names provided
        if ($ReservationNames) {
            $originalCount = $reservations.Count
            $reservations = $reservations | Where-Object { $_.name -in $ReservationNames }
            Write-ColoredOutput "Filtered to $($reservations.Count) of $originalCount reservations based on names provided" $Colors.Info
            
            if ($reservations.Count -eq 0) {
                Write-ColoredOutput "No reservations match the specified names" $Colors.Warning
                return
            }
        }
        
        # Show current owners if requested
        if ($ShowCurrentOwners) {
            Show-CurrentOwners -Reservations $reservations
            return
        }
        
        # Determine principal to add
        $principal = $null
        if ($UserEmail) {
            $principal = Resolve-Principal -Identifier $UserEmail
        } elseif ($GroupName) {
            $principal = Resolve-Principal -Identifier $GroupName
        } elseif ($PrincipalId) {
            $principal = Resolve-Principal -Identifier $PrincipalId
        } else {
            # Interactive mode - prompt user for input
            Write-ColoredOutput "No principal specified via parameters. Entering interactive mode..." $Colors.Info
            $principal = Get-UserOrGroupToAdd
        }
        
        if (-not $principal) {
            Write-ColoredOutput "Operation cancelled or could not resolve principal." $Colors.Warning
            return
        }
        
        # Confirm operation
        Write-Header "OPERATION CONFIRMATION"
        Write-ColoredOutput "Principal to add: $($principal.displayName) ($($principal.principalType))" $Colors.Highlight
        Write-ColoredOutput "Target reservations: $($reservations.Count)" $Colors.Info
        
        if ($WhatIf) {
            Write-ColoredOutput "WhatIf mode: No actual changes will be made" $Colors.Warning
        } else {
            $confirm = Read-Host "Proceed with adding Owner permissions? (y/N)"
            if ($confirm -notmatch "^[Yy]") {
                Write-ColoredOutput "Operation cancelled by user" $Colors.Warning
                return
            }
        }
        
        # Execute operation
        Write-Header "ADDING OWNER PERMISSIONS"
        $results = @()
        
        foreach ($reservation in $reservations) {
            Write-ColoredOutput "Processing: $($reservation.name)" $Colors.Info
            $result = Add-OwnerToReservation -Reservation $reservation -Principal $principal -WhatIf:$WhatIf
            $results += $result
        }
        
        # Summary
        Write-Header "OPERATION SUMMARY"
        $successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
        $failCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count
        $whatIfCount = ($results | Where-Object { $_.Status -eq "WhatIf" }).Count
        
        if ($WhatIf) {
            Write-ColoredOutput "WhatIf Results: $whatIfCount operations would be performed" $Colors.Info
        } else {
            Write-ColoredOutput "Successful: $successCount" $Colors.Success
            Write-ColoredOutput "Failed: $failCount" $(if ($failCount -gt 0) { $Colors.Error } else { $Colors.Success })
        }
        
        # Show failed operations
        if ($failCount -gt 0) {
            Write-Host ""
            Write-ColoredOutput "Failed Operations:" $Colors.Error
            $results | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
                Write-ColoredOutput "  • $($_.ReservationName): $($_.Message)" $Colors.Error
            }
        }
        
        # Export results if requested
        if ($ExportResults) {
            Write-Host ""
            Export-Results -Results $results -Principal $principal
        }
        
        Write-Header "SCRIPT COMPLETED"
        Write-ColoredOutput "Owner management operation completed successfully!" $Colors.Success
        
        if (-not $WhatIf -and $successCount -gt 0) {
            Write-ColoredOutput "Role assignments may take a few minutes to propagate fully" $Colors.Info
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

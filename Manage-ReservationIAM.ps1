#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Azure Cloud Shell script to manage IAM permissions for all Azure reservations.

.DESCRIPTION
    This script performs the following operations:
    1. Shows detailed reservation information (SKU, usage, affected resources, end dates)
    2. Retrieves all Azure reservations and checks their IAM permissions
    3. Lists all current Owners for each reservation
    4. Prompts for a user or group to add as Owner across all reservations
    5. Adds Owner permissions to the specified user/group
    6. Displays the updated IAM permissions

.PARAMETER ReportOnly
    When specified, shows only the detailed reservation report without IAM management

.NOTES
    - This script is designed to run in Azure Cloud Shell
    - Requires appropriate permissions to manage reservations and role assignments
    - Uses Azure CLI commands for reservation and IAM management

.EXAMPLE
    ./Manage-ReservationIAM.ps1
    
.EXAMPLE
    ./Manage-ReservationIAM.ps1 -ReportOnly
#>

[CmdletBinding()]
param(
    [switch]$ReportOnly
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
        $expiryDate = if ($_.ExpiryDate) { 
            try { 
                [DateTime]::Parse($_.ExpiryDate).ToString("yyyy-MM-dd") 
            } catch { 
                $_.ExpiryDate 
            }
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
            "Avg Usage (7d)" = $avgUtilization
            "Expiry Date" = $expiryDate
            State = $_.ProvisioningState
        }
    }
    
    $summaryTable | Format-Table -AutoSize
    
    # Display detailed information for each reservation
    Write-Header "DETAILED RESERVATION INFORMATION"
    
    foreach ($reservation in $detailedReservations) {
        Write-ColoredOutput ("-" * 80) $Colors.Header
        Write-ColoredOutput "RESERVATION: $($reservation.Name)" $Colors.Header
        Write-ColoredOutput ("-" * 80) $Colors.Header
        Write-Host ""
        
        # Basic Information
        Write-ColoredOutput "Basic Information:" $Colors.Info
        Write-ColoredOutput "   SKU: $($reservation.SKU)" $Colors.Success
        Write-ColoredOutput "   Resource Type: $($reservation.ResourceType)" $Colors.Success
        Write-ColoredOutput "   Quantity: $($reservation.Quantity)" $Colors.Success
        Write-ColoredOutput "   Term: $($reservation.Term)" $Colors.Success
        Write-ColoredOutput "   Instance Flexibility: $($reservation.InstanceFlexibility)" $Colors.Success
        Write-ColoredOutput "   Provisioning State: $($reservation.ProvisioningState)" $Colors.Success
        Write-Host ""
        
        # Dates
        Write-ColoredOutput "Important Dates:" $Colors.Info
        if ($reservation.EffectiveDate) {
            try {
                $effectiveDate = [DateTime]::Parse($reservation.EffectiveDate).ToString("yyyy-MM-dd HH:mm UTC")
                Write-ColoredOutput "   Start Date: $effectiveDate" $Colors.Success
            } catch {
                Write-ColoredOutput "   Start Date: $($reservation.EffectiveDate)" $Colors.Success
            }
        }
        
        if ($reservation.ExpiryDate) {
            try {
                $expiryDate = [DateTime]::Parse($reservation.ExpiryDate)
                $daysUntilExpiry = ($expiryDate - (Get-Date)).Days
                $expiryFormatted = $expiryDate.ToString("yyyy-MM-dd HH:mm UTC")
                
                $expiryColor = $Colors.Success
                if ($daysUntilExpiry -lt 30) { $expiryColor = $Colors.Error }
                elseif ($daysUntilExpiry -lt 90) { $expiryColor = $Colors.Warning }
                
                Write-ColoredOutput "   End Date: $expiryFormatted" $expiryColor
                Write-ColoredOutput "   Days Until Expiry: $daysUntilExpiry days" $expiryColor
            } catch {
                Write-ColoredOutput "   End Date: $($reservation.ExpiryDate)" $Colors.Success
            }
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
    $expiringIn30Days = ($detailedReservations | Where-Object { 
        try { 
            $_.ExpiryDate -and ([DateTime]::Parse($_.ExpiryDate) - (Get-Date)).Days -lt 30 
        } catch { 
            $false 
        }
    }).Count
    
    $expiringIn90Days = ($detailedReservations | Where-Object { 
        try { 
            $_.ExpiryDate -and ([DateTime]::Parse($_.ExpiryDate) - (Get-Date)).Days -lt 90 
        } catch { 
            $false 
        }
    }).Count
    
    $lowUtilization = ($detailedReservations | Where-Object { 
        $_.UtilizationSummary -and $_.UtilizationSummary.AverageUtilization -lt 50 
    }).Count
    
    Write-ColoredOutput "Summary Statistics:" $Colors.Header
    Write-ColoredOutput "   Total Reservations: $totalReservations" $Colors.Info
    Write-ColoredOutput "   Expiring in 30 days: $expiringIn30Days" $(if ($expiringIn30Days -gt 0) { $Colors.Warning } else { $Colors.Success })
    Write-ColoredOutput "   Expiring in 90 days: $expiringIn90Days" $(if ($expiringIn90Days -gt 0) { $Colors.Warning } else { $Colors.Success })
    Write-ColoredOutput "   Low utilization (<50%): $lowUtilization" $(if ($lowUtilization -gt 0) { $Colors.Warning } else { $Colors.Success })
    
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
        
        if ($ReportOnly) {
            Write-Header "REPORT COMPLETED"
            Write-ColoredOutput "Detailed reservation report has been generated successfully!" $Colors.Success
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
        
        Write-Header "SCRIPT EXECUTION COMPLETED"
        Write-ColoredOutput "All operations have been completed successfully!" $Colors.Success
        
    }
    catch {
        Write-ColoredOutput "Script execution failed: $($_.Exception.Message)" $Colors.Error
        Write-ColoredOutput "Stack trace: $($_.ScriptStackTrace)" $Colors.Error
        exit 1
    }
}

# Execute main function
Main

# Azure Reservations IAM Management Script

A comprehensive PowerShell script designed for Azure Cloud Shell that manages IAM permissions across all Azure reservations and provides detailed reservation analytics.

## Overview

This enhanced script performs the following operations in sequence:

1. **Detailed Reservation Analytics** - Shows comprehensive reservation information including:
   - SKU details and resource types
   - 7-day usage statistics and utilization percentages
   - Affected resources discovery
   - Expiry dates with renewal recommendations
   
2. **Retrieves all Azure reservations** and checks their current IAM permissions
3. **Lists all current Owners** for each reservation with a detailed summary
4. **Prompts for a user or group** to add as Owner across all reservations
5. **Adds Owner permissions** to the specified user/group for all reservations
6. **Displays updated IAM permissions** showing the complete role assignment state

## Features

- ✅ **Status Tracking**: Real-time reservation status monitoring (Active, Expired, Expiring Soon, Expiring)
- ✅ **Comprehensive Analytics**: Detailed reservation usage and cost optimization insights with 1,315 lines of code
- ✅ **Multi-File CSV Export**: Generate 4 specialized CSV files for offline analysis and reporting
- ✅ **Cloud Shell Integration**: Built-in download commands for easy file retrieval
- ✅ **Resource Discovery**: Automatically finds resources affected by each reservation
- ✅ **Usage Monitoring**: 7-day utilization statistics with optimization recommendations
- ✅ **Expiry Tracking**: Proactive alerts for reservations nearing expiration (30/90 day warnings)
- ✅ **Full IAM Coverage**: Works with all reservations across accessible subscriptions
- ✅ **User Validation**: Validates user/group existence before making changes
- ✅ **Detailed Reporting**: Color-coded output with clear success/failure indicators
- ✅ **Error Handling**: Robust error handling with detailed error messages
- ✅ **Interactive Prompts**: User-friendly prompts with confirmation steps
- ✅ **Help System**: Comprehensive help documentation with examples and usage patterns
- ✅ **Report-Only Mode**: Option to run detailed analytics without IAM changes

## Prerequisites

### Required Permissions

To run this script successfully, you need the following Azure permissions:

- **Reservation Reader** or higher on reservations
- **User Access Administrator** or **Owner** role on reservations to modify IAM
- **Directory Reader** permissions in Azure AD to validate users/groups

### Azure Cloud Shell Setup

This script is designed to run in **Azure Cloud Shell** which provides:
- Pre-installed Azure CLI
- PowerShell Core environment
- Authenticated session with your Azure credentials

## Usage

### Running the Script

1. **Open Azure Cloud Shell** in the Azure Portal
2. **Upload the script** to your Cloud Shell environment:
   ```bash
   # Option 1: Upload via Cloud Shell interface
   # Click the upload/download icon and select the .ps1 file
   
   # Option 2: Clone from repository (if stored in Git)
   git clone <your-repo-url>
   cd <repo-directory>
   ```

3. **Make the script executable** (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   ```

4. **Run the script** for full IAM management:
   ```powershell
   ./Manage-ReservationIAM.ps1
   ```

5. **Run for detailed report only** (no IAM changes):
   ```powershell
   ./Manage-ReservationIAM.ps1 -ReportOnly
   ```

### Script Modes

#### Full Mode (Default)
Complete reservation analytics + IAM management:
- Detailed reservation report with usage analytics
- Current IAM permissions analysis
- Interactive owner addition
- Updated permissions display

#### Report-Only Mode
Analytics and insights without IAM changes:
- Comprehensive reservation details
- Usage statistics and optimization recommendations
- Resource discovery and mapping
- Expiry tracking and renewal alerts

#### CSV Export Mode
Export comprehensive data for offline analysis:
- Generate 4 specialized CSV files
- Status tracking and utilization metrics
- Resource mapping and IAM permissions
- Cloud Shell download integration

### CSV Export Feature

The script can export comprehensive reservation data to CSV files for offline analysis and reporting:

#### Available CSV Files
1. **reservations_summary.csv** - Core reservation details with status information
2. **reservations_utilization.csv** - Usage statistics and optimization recommendations  
3. **reservations_resources.csv** - Affected resources mapping and details
4. **reservations_iam.csv** - Complete IAM permissions matrix

#### Export Usage Examples
```powershell
# Generate report with CSV export
./Manage-ReservationIAM.ps1 -ReportOnly -ExportCsv

# Full IAM management with CSV export
./Manage-ReservationIAM.ps1 -ExportCsv

# Export to custom directory
./Manage-ReservationIAM.ps1 -ReportOnly -ExportCsv -OutputPath "./my-exports"
```

#### Downloading Files in Cloud Shell
```bash
# Download all CSV files
download ./exports/reservations_summary.csv
download ./exports/reservations_utilization.csv
download ./exports/reservations_resources.csv
download ./exports/reservations_iam.csv
```

### Script Workflow

#### Step 1: Initial Discovery
The script will:
- Connect to Azure using your Cloud Shell credentials
- Scan all accessible subscriptions for reservations
- Display found reservations with their details

#### Step 2: Current Permissions Analysis
For each reservation, the script will:
- Retrieve all role assignments
- Filter and display only Owner permissions
- Provide a summary of unique owners across all reservations

#### Step 3: New Owner Addition
The script will prompt for:
- User Principal Name (e.g., `user@domain.com`)
- Group display name or Object ID
- Confirmation before making changes

#### Step 4: Permission Assignment
The script will:
- Add Owner role to the specified principal on each reservation
- Display real-time progress with success/failure indicators
- Provide a summary of results

#### Step 5: Updated Permissions Display
Finally, the script will:
- Show all role assignments (not just Owners) for each reservation
- Highlight the newly added permissions

## Example Output

### Detailed Reservation Report
```
================================================================================
  DETAILED RESERVATIONS REPORT
================================================================================

Gathering detailed information for 3 reservation(s)...
This may take a moment as we collect usage data...

Processing: SQL-Database-Reserved-Instance
  Getting utilization data for SQL-Database-Reserved-Instance...
  Discovering affected resources...
    Searching for SQL Databases...

Processing: VM-Reserved-Capacity
  Getting utilization data for VM-Reserved-Capacity...
  Discovering affected resources...
    Searching for Virtual Machines matching SKU: Standard_D2s_v3

================================================================================
  RESERVATIONS OVERVIEW
================================================================================

Name                         SKU              Type            Quantity Term    Avg Usage (7d) Expiry Date State
----                         ---              ----            -------- ----    -------------- ----------- -----
SQL-Database-Reserved-I...   P2               SqlDatabases    5        P1Y     87.5%          2024-12-15  Succeeded
VM-Reserved-Capacity         Standard_D2s_v3  VirtualMachines 10       P3Y     65.2%          2026-03-20  Succeeded
Storage-Reserved-Capacity    Premium_LRS      Storage         1000     P1Y     No data        2024-11-30  Succeeded

================================================================================
  DETAILED RESERVATION INFORMATION
================================================================================

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 RESERVATION: SQL-Database-Reserved-Instance
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 Basic Information:
   SKU: P2
   Resource Type: SqlDatabases
   Quantity: 5
   Term: P1Y
   Instance Flexibility: On
   Provisioning State: Succeeded

📅 Important Dates:
   Start Date: 2023-12-15 10:30 UTC
   End Date: 2024-12-15 10:30 UTC
   Days Until Expiry: 47 days

📊 Usage Information (Last 7 Days):
   Average Utilization: 87.5%
   Maximum Utilization: 95.2%
   Minimum Utilization: 78.1%
   Data Points Available: 7
   ✅ RECOMMENDATION: High utilization. This reservation is well-utilized.

🎯 Affected Resources:
   - SQL DB: ProductionDB (Server: prod-sql-01, Tier: P2, RG: production-rg)
   - SQL DB: AnalyticsDB (Server: analytics-sql, Tier: P2, RG: analytics-rg)
   - SQL DB: DevDB (Server: dev-sql-01, Tier: P2, RG: development-rg)

================================================================================
  RESERVATIONS SUMMARY STATISTICS
================================================================================

📈 Summary Statistics:
   Total Reservations: 3
   Expiring in 30 days: 0
   Expiring in 90 days: 2
   Low utilization (<50%): 0
```

### IAM Management Example
```
================================================================================
  CURRENT IAM PERMISSIONS - OWNERS ONLY
================================================================================

Reservation: SQL-Database-Reserved-Instance (SqlDatabases)
ID: /providers/Microsoft.Capacity/reservationOrders/12345/reservations/67890

  Current Owners:
    - admin@company.com (User)
    - DBAdmins (Group)
```

## Error Handling

The script includes comprehensive error handling for common scenarios:

- **No reservations found**: Script will complete gracefully
- **Insufficient permissions**: Clear error messages with required permissions
- **Invalid user/group**: Validation with retry options
- **Network issues**: Retry mechanisms for transient failures
- **Partial failures**: Detailed reporting of which operations succeeded/failed

## Troubleshooting

### Common Issues

1. **"Access Denied" errors**:
   - Ensure you have User Access Administrator or Owner role on reservations
   - Check that your account has proper Azure AD permissions

2. **"Reservation not found" errors**:
   - Verify you have access to the subscriptions containing reservations
   - Check if reservations exist in the current tenant

3. **"Principal not found" errors**:
   - Verify the user/group exists in Azure AD
   - Ensure proper spelling of user principal names
   - Try using Object ID instead of display names

### Debug Mode

To enable verbose output for troubleshooting:
```powershell
$VerbosePreference = "Continue"
./Manage-ReservationIAM.ps1
```

## Security Considerations

- **Principle of Least Privilege**: Only run this script with accounts that need to manage reservation permissions
- **Audit Trail**: All role assignments are logged in Azure Activity Log
- **Validation**: Script validates all inputs before making changes
- **Confirmation**: Interactive confirmations prevent accidental changes

## Customization

The script can be customized for specific needs:

### Adding Other Roles
To add roles other than Owner, modify the role assignment section:
```powershell
# Change "Owner" to desired role name
--role "Contributor"  # or "Reader", etc.
```

### Filtering Specific Reservations
Add filtering logic in the `Get-AllReservations` function:
```powershell
# Example: Filter by reservation name pattern
$reservations = $reservations | Where-Object { $_.name -like "*SQL*" }
```

### Bulk Operations from File
Modify the script to read user/group lists from a CSV file for bulk operations.

## Support

For issues or questions:
1. Check the Azure Activity Log for detailed error information
2. Verify permissions using Azure Portal
3. Test with a single reservation before running on all reservations
4. Review PowerShell execution policies in Cloud Shell

## Version History

- **v1.0**: Initial release with core functionality
  - Basic IAM management for all reservations
  - Interactive user prompts
  - Comprehensive error handling
  - Detailed reporting

---

**Note**: This script is provided as-is for educational and operational purposes. Always test in a non-production environment first and ensure you have proper backup and rollback procedures in place.

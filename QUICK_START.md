# Quick Start Guide for Azure Reservations IAM Management

## Prerequisites Checklist

Before running the script, ensure you have:

- [ ] Access to Azure Cloud Shell
- [ ] User Access Administrator or Owner role on Azure reservations
- [ ] Directory Reader permissions in Azure AD
- [ ] At least one Azure reservation in your accessible subscriptions

## Quick Start Steps

### 1. Open Azure Cloud Shell
Navigate to [shell.azure.com](https://shell.azure.com) or use the Cloud Shell icon in the Azure Portal.

### 2. Upload the Script
```bash
# Upload the Manage-ReservationIAM.ps1 file using the Cloud Shell upload feature
# Or use git if you have it in a repository
```

### 3. Set Execution Policy (if needed)
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### 4. Run the Script

**For detailed report only** (no IAM changes):
```powershell
./Manage-ReservationIAM.ps1 -ReportOnly
```

**For full IAM management** (includes detailed report + IAM changes):
```powershell
./Manage-ReservationIAM.ps1
```

### 5. Script Modes

#### Report-Only Mode (`-ReportOnly`)
Perfect for regular monitoring and analysis:
- Comprehensive reservation analytics
- Usage optimization recommendations  
- Resource discovery and mapping
- Expiry alerts and renewal planning
- **No IAM changes made**

#### Full Mode (Default)
Complete management including:
- All report-only features
- Current IAM permissions analysis
- Interactive owner addition
- Updated permissions verification

### 6. Follow the Interactive Prompts

The script will guide you through:
1. **Analytics Phase**: Detailed reservation information and recommendations
2. **Discovery Phase**: Current reservations and their owners (full mode only)
3. **Input Phase**: Prompting for new owner (full mode only)
4. **Execution Phase**: Adding permissions with progress updates (full mode only)
5. **Results Phase**: Showing updated permissions (full mode only)

## Sample User Inputs

When prompted for a user/group, you can enter:
- `user@yourcompany.com` (User Principal Name)
- `Finance Team` (Group display name)
- `12345678-1234-1234-1234-123456789012` (Object ID)

## Expected Output Flow

### Report-Only Mode
1. **Discovery Phase**: Lists all found reservations with basic info
2. **Analytics Phase**: Detailed information including:
   - SKU details and resource types
   - 7-day usage statistics
   - Affected resources discovery
   - Expiry dates with recommendations
3. **Summary Phase**: Utilization insights and optimization recommendations

### Full Mode  
1. **Analytics Phase**: Complete detailed report (as above)
2. **IAM Discovery**: Shows existing owners
3. **Input Phase**: Prompts for new owner
4. **Validation**: Confirms the user/group exists
5. **Execution**: Adds permissions with progress updates
6. **Results**: Shows updated permissions

## Troubleshooting Quick Fixes

### If you get "Access Denied":
```powershell
# Check your current role assignments
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table
```

### If no reservations are found:
```powershell
# Check available subscriptions
az account list --output table

# Switch to a different subscription if needed
az account set --subscription "Your-Subscription-Name"
```

### If user validation fails:
```powershell
# Search for users/groups manually
az ad user list --filter "startswith(displayName,'PartialName')" --output table
az ad group list --filter "startswith(displayName,'PartialName')" --output table
```

## Post-Execution Verification

After running the script, verify the changes:

1. **Via Azure Portal**:
   - Navigate to Cost Management + Billing > Reservations
   - Select a reservation and check Access control (IAM)

2. **Via Azure CLI**:
   ```powershell
   az role assignment list --scope "/providers/Microsoft.Capacity/reservationOrders/YOUR-ORDER-ID/reservations/YOUR-RESERVATION-ID" --output table
   ```

## Safety Notes

- The script asks for confirmation before making changes
- All operations are logged in Azure Activity Log
- You can always remove permissions later if needed
- Test with a single reservation first if you're unsure

For detailed documentation, see the main README.md file.

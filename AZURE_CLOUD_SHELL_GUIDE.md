# Running the Azure Reservations Script in Azure Cloud Shell

## 📋 Prerequisites Checklist

Before running the script, ensure you have:

- [ ] **Azure Account** with appropriate permissions
- [ ] **User Access Administrator** or **Owner** role on reservations you want to manage
- [ ] **Directory Reader** permissions in Azure AD (to validate users/groups)
- [ ] At least one Azure reservation in your accessible subscriptions

## 🚀 Step-by-Step Execution Guide

### Step 1: Access Azure Cloud Shell

#### Option A: Via Azure Portal
1. **Sign in** to the [Azure Portal](https://portal.azure.com)
2. **Click the Cloud Shell icon** (>_) in the top navigation bar
3. **Select PowerShell** when prompted (recommended for this script)
4. **Wait for initialization** (first-time setup may take a few moments)

#### Option B: Direct Access
1. **Navigate** to [shell.azure.com](https://shell.azure.com)
2. **Sign in** with your Azure credentials
3. **Choose PowerShell** environment

### Step 2: Upload the Script

#### Method A: File Upload (Recommended)
1. **Click the Upload/Download files icon** (folder with arrow) in Cloud Shell toolbar
2. **Select "Upload"**
3. **Choose the file**: `Manage-ReservationIAM.ps1`
4. **Wait for upload** to complete
5. **Verify upload**: 
   ```powershell
   ls -la Manage-ReservationIAM.ps1
   ```

#### Method B: Create File Directly
1. **Create the file**:
   ```powershell
   nano Manage-ReservationIAM.ps1
   ```
2. **Copy and paste** the entire script content
3. **Save and exit**: `Ctrl+X`, then `Y`, then `Enter`

#### Method C: Git Clone (if stored in repository)
```powershell
git clone https://github.com/yourusername/your-repo.git
cd your-repo
```

### Step 3: Set Execution Policy (if needed)

```powershell
# Allow script execution for current session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Step 4: Verify Your Azure Context

```powershell
# Check current subscription
az account show

# List available subscriptions
az account list --output table

# Switch subscription if needed
az account set --subscription "Your-Subscription-Name-or-ID"
```

### Step 5: Test Basic Permissions

```powershell
# Verify you can list reservations
az reservations reservation list --query "[].{name:name,resourceType:reservedResourceType}" --output table

# Check your role assignments (optional)
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table
```

### Step 6: Run the Script

#### For Analytics Report Only (Recommended First Run)
```powershell
./Manage-ReservationIAM.ps1 -ReportOnly
```

#### For Full IAM Management
```powershell
./Manage-ReservationIAM.ps1
```

## 📊 What to Expect

### First Run (Report-Only Mode)
The script will:
1. **Discover reservations** across all accessible subscriptions
2. **Display detailed analytics** including:
   - SKU information and quantities
   - Usage statistics (last 7 days)
   - Affected resources discovery
   - Expiry dates and renewal recommendations
3. **Provide optimization insights** based on utilization
4. **Show summary statistics** and alerts

### Full Mode Run
After the analytics report, the script will:
1. **Show current IAM owners** for each reservation
2. **Prompt for new user/group** to add as owner
3. **Validate the principal** exists in Azure AD
4. **Add Owner permissions** to all reservations
5. **Display updated permissions** for verification

## 🛠 Troubleshooting Common Issues

### Issue: "Access Denied" Errors
**Solution:**
```powershell
# Check your permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) --scope "/providers/Microsoft.Capacity" --output table
```
**Required:** User Access Administrator or Owner role on reservations

### Issue: "No Reservations Found"
**Solution:**
```powershell
# Check subscription access
az account list --output table

# Verify reservations exist
az reservations reservation-order list --output table
```

### Issue: "Principal Not Found" During IAM Addition
**Solutions:**
```powershell
# Search for users
az ad user list --filter "startswith(displayName,'PartialName')" --output table

# Search for groups  
az ad group list --filter "startswith(displayName,'PartialName')" --output table

# Use Object ID instead of display name
```

### Issue: Script Execution Policy Error
**Solution:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
```

## 🔧 Advanced Usage

### Running on Specific Subscriptions
```powershell
# Set specific subscription context
az account set --subscription "Production-Subscription"
./Manage-ReservationIAM.ps1 -ReportOnly
```

### Scheduled Execution (for monitoring)
```powershell
# Create a wrapper script for regular monitoring
echo './Manage-ReservationIAM.ps1 -ReportOnly | Out-File "reservation-report-$(Get-Date -Format "yyyy-MM-dd").txt"' > run-weekly-report.ps1
```

### Bulk User Addition (manual modification)
Modify the script to read from a CSV file for bulk operations:
```powershell
# Example: Create users.csv with columns: UserPrincipalName, DisplayName
# Then modify the script to loop through the CSV
```

## 📋 Best Practices

### 1. Security
- ✅ **Run report-only first** to understand current state
- ✅ **Test with limited scope** before bulk operations
- ✅ **Use principle of least privilege** for the executing account
- ✅ **Review changes** in Azure Activity Log after execution

### 2. Monitoring
- 📅 **Run weekly reports** to track utilization trends
- 📊 **Monitor expiry dates** proactively (90-day alerts)
- 🔍 **Review usage recommendations** for cost optimization
- 📝 **Document changes** made through the script

### 3. Maintenance
- 🔄 **Keep script updated** with latest Azure CLI features
- 📦 **Version control** your modifications
- 🧪 **Test in non-production** first
- 📚 **Update documentation** for custom modifications

## 🆘 Support Resources

### Azure Documentation
- [Azure Reservations Overview](https://docs.microsoft.com/azure/cost-management-billing/reservations/save-compute-costs-reservations)
- [Azure Cloud Shell Documentation](https://docs.microsoft.com/azure/cloud-shell/overview)
- [Azure CLI Reference](https://docs.microsoft.com/cli/azure/)

### Script-Specific Help
- **View script help**: `Get-Help ./Manage-ReservationIAM.ps1 -Detailed`
- **Check syntax**: Use the validation commands from our development
- **Error logs**: Available in Azure Activity Log under subscription

---

**🎯 Pro Tip**: Start with `-ReportOnly` mode to familiarize yourself with your reservation landscape before making any IAM changes!

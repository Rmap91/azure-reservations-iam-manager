# Azure CLI Reservation Access Fix

## 🔧 **Issue Fixed**

The script has been updated to handle the Azure CLI reservation listing requirements correctly.

## 🚀 **Updated Script Features**

### **Multi-Method Reservation Discovery**
1. **Primary Method**: Uses `az reservations reservation-order list` followed by individual reservation queries
2. **Fallback Method**: Provides guidance for alternative access methods
3. **Error Handling**: Clear troubleshooting steps for permission issues

### **What Changed**
- ✅ Fixed the Azure CLI command sequence
- ✅ Added proper error handling for access issues
- ✅ Improved user guidance for permission problems
- ✅ Updated utilization data retrieval method

## 🔍 **Try the Updated Script**

Re-upload the updated script to Azure Cloud Shell and try:

```powershell
# Get the latest version from GitHub
curl -o Manage-ReservationIAM.ps1 https://raw.githubusercontent.com/Rmap91/azure-reservations-iam-manager/master/Manage-ReservationIAM.ps1

# Run the updated script
./Manage-ReservationIAM.ps1 -ReportOnly
```

## 🛠 **If You Still Get Permission Issues**

### **Check Your Current Context**
```powershell
# Verify current subscription
az account show

# List all accessible subscriptions
az account list --output table

# Switch to subscription with reservations
az account set --subscription "your-subscription-name"
```

### **Verify Reservation Access**
```powershell
# Test reservation order access
az reservations reservation-order list --output table

# If that fails, check your role assignments
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table
```

### **Required Permissions**
For the script to work, you need:
- **Reservation Reader** (or higher) role on reservation orders
- **Access to the subscription** containing the reservations
- **Proper tenant context** if reservations are in different tenants

### **Alternative: Azure Portal Method**
If CLI access is limited, use the Azure Portal:
1. Go to **Cost Management + Billing**
2. Navigate to **Reservations**
3. View your reservation details there
4. Use the script's IAM features by providing reservation IDs manually

## 📊 **Expected Behavior Now**

The updated script will:
1. ✅ Try multiple methods to find reservations
2. ✅ Provide clear error messages if access is limited
3. ✅ Give specific troubleshooting guidance
4. ✅ Work with whatever level of access you have

## 🔄 **Quick Test Commands**

```powershell
# Quick permission test
az reservations reservation-order list --query "[].{name:name,displayName:displayName}" --output table

# If that works, the script should work too
./Manage-ReservationIAM.ps1 -ReportOnly
```

The script is now much more robust and should handle various Azure CLI access scenarios! 🎯

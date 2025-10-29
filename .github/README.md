# Azure Reservations IAM Management

A comprehensive PowerShell script for Azure Cloud Shell that manages IAM permissions and provides detailed analytics for Azure reservations.

## 🚀 Features

- **📊 Detailed Reservation Analytics** - SKU details, usage statistics, expiry tracking
- **🎯 Resource Discovery** - Automatically finds affected resources
- **⚙️ IAM Management** - Add owners across all reservations
- **📈 Usage Monitoring** - 7-day utilization insights with recommendations
- **🔧 Dual Modes** - Report-only or full IAM management

## 📁 Files

- `Manage-ReservationIAM.ps1` - Main PowerShell script
- `README.md` - Complete documentation
- `QUICK_START.md` - Quick start guide
- `AZURE_CLOUD_SHELL_GUIDE.md` - Step-by-step Azure Cloud Shell instructions
- `CLOUD_SHELL_FIX.md` - Troubleshooting guide
- `ENHANCEMENT_SUMMARY.md` - Feature enhancement details

## 🏃‍♂️ Quick Start

### For Azure Cloud Shell:

1. Upload `Manage-ReservationIAM.ps1` to Azure Cloud Shell
2. Run analytics only: `./Manage-ReservationIAM.ps1 -ReportOnly`
3. Run with IAM management: `./Manage-ReservationIAM.ps1`

## 📋 Prerequisites

- Azure Cloud Shell access
- User Access Administrator or Owner role on reservations
- Directory Reader permissions in Azure AD

## 📊 Sample Output

```
RESERVATIONS OVERVIEW
Name                    SKU           Type          Quantity  Avg Usage (7d)  Expiry Date
SQL-Reserved-Instance   P2            SqlDatabases  5         87.5%          2024-12-15
VM-Reserved-Capacity    Standard_D2s  VirtualMach   10        65.2%          2026-03-20
```

## 🛠 Usage Examples

```powershell
# Get detailed analytics report only
./Manage-ReservationIAM.ps1 -ReportOnly

# Full functionality with IAM management
./Manage-ReservationIAM.ps1
```

## 📚 Documentation

- See `README.md` for complete documentation
- See `QUICK_START.md` for immediate usage
- See `AZURE_CLOUD_SHELL_GUIDE.md` for detailed setup instructions

## 🎯 Key Benefits

- **Cost Optimization** - Usage analytics and recommendations
- **Security Management** - Centralized IAM control
- **Proactive Monitoring** - Expiry alerts and renewal planning
- **Resource Discovery** - Automatic mapping of affected resources

---

**Ready for Azure Cloud Shell deployment! 🌟**

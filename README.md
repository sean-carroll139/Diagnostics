# 🧰 Server Diagnostics & Automation Scripts

This repository contains a collection of Linux- and Windows-based diagnostic and automation scripts developed to support server hardware testing, RMA verification, and component validation at Ahead. These tools were created for internal use on custom test benches and enterprise environments, streamlining the analysis of returned parts and accelerating root cause identification.

## 🔧 Key Features

- **Drive Testing Tools**
  - Secure NVMe wipe & validation script (Linux)
  - U.3, SATA, SAS drive read/write and endurance tests using `fio`
  - SMART data collection and logging

- **Network Tools**
  - Multi-NIC link and throughput tester
  - Interface verification and burn-in automation

- **Automation Utilities**
  - Batch RMA logger with structured output
  - USB drive automount for diagnostics on boot
  - Auto-inventory & labeling script for asset tagging

- **System Utilities**
  - Fan and thermals script for evaluating airflow issues
  - DIMM failure detection loop for HPE/Dell servers
  - RAID rebuild and verification helper (Windows/Linux hybrid)

## 📁 Repository Structure

/
├── drive_tools/
│ ├── wipe_nvme.sh
│ ├── fio_u3_test.sh
│ └── smart_scan.sh
├── network_tools/
│ ├── nic_burnin.sh
│ └── verify_nic_config.sh
├── automation/
│ ├── rma_logger.sh
│ └── auto_inventory.sh
├── system_utils/
│ ├── fancheck.sh
│ ├── dimm_loop_test.ps1
│ └── raid_verify.sh
├── LICENSE
└── README.md


> 🔒 **Disclaimer**: These tools are optimized for Ahead’s lab infrastructure and testing environments. They may need modification for use in other contexts.

## 🧪 Usage

Clone this repo to your test server or bootable USB diagnostics environment:

```bash
git clone https://github.com/sean-carroll139/server-diagnostics.git
cd server-diagnostics

Run any script with:
bash ./path/to/script.sh

For PowerShell:
.\system_utils\dimm_loop_test.ps1

NOTE: Some scripts require elevated permissions or specific dependencies (fio, smartmontools, etc.). Check the headers of each script for prerequisites.

🛠️ Dependencies
fio

smartctl

lsblk, nvme-cli, sg3_utils

PowerShell 5+ (for Windows scripts)

Root/admin access on test machines

✅ Tested Hardware
Scripts have been tested on:

Custom-built Ahead test rigs

Dell PowerEdge R740/R750

HPE ProLiant DL360/DL380 Gen10

Lenovo ThinkSystem SR650

Mixed SSDs, HDDs, NVMe, U.3 drives

🤝 Contributions
Pull requests are welcome for extending support to additional hardware, or general improvements. For large changes, please open an issue first to discuss what you would like to change.

📜 License
MIT License. See LICENSE for details.

Maintained by Sean Carroll
📍 Server Diagnostics Specialist @ Ahead


---

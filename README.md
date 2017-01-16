
# Get-SPFarmLogs

**This script permits to collect multiple kind of logs in a SharePoint farm or for a group of servers. You have an extended farm and you need to collect logs in each one of your 5, 6 or 10 servers. It’s a waste of time to logon one by one to do that!! With this script you can collect Farm’s Logs to a centralized folder.**

## Syntax

```powershell 
  .\get-spfarmlogs.ps1 -user ocsi\administrator `
  -EventsDir "C:\folder\logs" `
  -ULSstarttime "01/13/2017 08:30" `
  -ULSendtime "01/13/2017 08:32" `
  -IISdate 17010 `
  -NoEvents:$false
  This command permits to gather all the logs : EventViewer, IIS and ULS log  in the folder "C:\folder\logs".
 ```
 ```powershell 
   .\get-spfarmlogs.ps1 -user ocsi\administrator `
   -EventsDir "C:\folder\logs" `
   -servers "SP,SP2" `
   -IISdate 17010 `
   -NoEvents:$false; 
    
    this command permits to gather the EventViewer and IIS logs in the folder "C:\folder\logs" for the servers SP and SP2, there is no ULS logs collected.
 
```

## Installation

**this is a script that need to be run in PowerShell UI like (PowerShell ISE) or a Powershell window. The loading of the SharePoint module is already included in the script.**


| Parameter     | Description      | default value    |
| ------------- | ---------------- | ----------------:|
| -user         | user with administrator rights on all the servers                                                        | N/A    |
| -NoEvents     | syntax: -NoEvents:$true or -NoEvents:$false indicate if Application or System event viewer are required  | $false |
| -EventsDir    | define the folder where the logs will be saved    | N/A |
| -IISdate      | define the wildcard value for the IIS logs to gather, i.e 17010 will collect all IIS logs between 170101 to 170109.| if not specified the IIS logs will not be collected     |
| -servers      | betwee "" specify the list of servers that will be collected, the separator is the coma (,)| if not specified all the servers of the farm will be collected   |
| -ULSstarttime | start time for the Merge-SPLogFile command  | N/A      |
| -ULSendtime   | end time for the Merge-SPLogFile command     | N/A      |






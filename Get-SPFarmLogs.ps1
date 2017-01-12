﻿######################################################################################################
        #        This script is entended to gather farm logs                                 #
        #        it will get logs from ULS , IIS based on date and EventViewer Application   #
        #        and System.                                                                 #
		#        Version 2.0                                                                 #
        #        provided by Miguel Godinho / Sharepoint SEE at Microsoft Support 06/01/2017 #
		# 		 last modification : 10/01/2017                                              #
######################################################################################################
<#
example
.\get-spfarmlogs.ps1 -user contoso\admincc -eventsdir "C:\collectfarmlogs\logs" -IISdate 160916 -ULSstarttime "06/30/20xx 18:30" -ULSendtime "06/30/20xx 19:30"

working date 
01/04/2017 16:00



#>

param (

	[Parameter(Mandatory=$false)]
    [string]
    $NoEvents=$true
    ,
    [parameter(Mandatory=$false)]
    [string] 
    $user="contoso\spsvc"
    ,
    [Parameter(Mandatory=$false)]
    [string] 
    $EventsDir="C:\share\_get-spfarmlogs\logs"
    ,
    [Parameter(Mandatory=$false)]
    [string]
    $IISdate="161208"
    , 
    [Parameter(Mandatory=$false)]
    [string]
    $ULSstarttime="" 
    ,
    [Parameter(Mandatory=$false)]
    [string]
    $ULSendtime=""
	,
    [Parameter(Mandatory=$false)]
    [string]
    $servers=""
    
)

$h=(Get-Host).UI.RawUI
$h.ForegroundColor="DarkYellow"
write-host("There is a syntax example");
write-host('get-spfarmlogs.ps1 -user "contoso\admincc" -eventsdir C:\collectfarmlogs\logs -IISdate 150910 -ULSstarttime "06/30/20xx 18:30" -ULSendtime "06/30/20xx 19:30"');
$h.BackgroundColor="black"
$h.ForegroundColor="green"

#$password =  read-host "Provide the password for the Admin Remote Servers " -AsSecureString ;

$password= ConvertTo-SecureString “Access1” -AsPlainText -Force

$user="contoso\spsvc"

$credential = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $password
$h.ForegroundColor="gray"

# load necessary modules
try{
# load SharePoint Module
if(-not(Get-PSSnapin | Where { $_.Name -eq "Microsoft.SharePoint.PowerShell"}))
{
    Add-PSSnapin Microsoft.SharePoint.Powershell -ea 0
}
# load IIS module
Import-Module webadministration

}
catch{
	$Error[0].Exception.Message
}




function GetEventsLogsApplication ([string]$server,[Management.Automation.PSCredential]$credential)
{
                $h.ForegroundColor="yellow"
                Write-Host("Getting Application logs from $server")
                $h.ForegroundColor="gray"
                if(!(Test-Connection -Quiet $server -Count 5)) {
                               throw "[$server] connection not available"
                }
                try {
                               
                               if ($server -eq $env:COMPUTERNAME) {
                                               return Get-WmiObject -Class:Win32_NTEventlogFile | where {$_.logfilename -eq "application"}
                               }

                               return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server -credential $credential | where {$_.logfilename -eq "application"}
                               }
                catch {
                               throw "[GetEventsLogsApplication][$server] (Ligne $($_.InvocationInfo.ScriptLineNumber)) $_"
                }
}

function GetEventsLogsSystem ([string]$server, [Management.Automation.PSCredential]$credential)
{
                
                $h.ForegroundColor="yellow"
                Write-Host("Getting System logs from $server")
                $h.ForegroundColor="gray"
                if(!(Test-Connection -Quiet $server -Count 5)) {
                               throw "[$server] connection not available"
                }
                try {
                               if ($server -eq $env:COMPUTERNAME) {
                                               return Get-WmiObject -Class:Win32_NTEventLogfile | where {$_.logfilename -eq "system"}
                               }

                               return Get-Wmiobject -Class:Win32_NTEventLogfile -ComputerName:$server  -Credential:$credential | where {$_.logfilename -eq "system"}
                }
                catch {
                               throw "[GetEventsLogsSystem][$server] (Ligne $($_.InvocationInfo.ScriptLineNumber)) $_"
                }
}

function GetIISlogs ([string]$server, [Management.Automation.PSCredential]$credential)
{
                $h.ForegroundColor="yellow";
                Write-Host("Getting IIS logs from $server");
                if(!(Test-Connection -Quiet $server -Count 5)) {
                               throw "[$server] connection not available";
                }
                try {
                               
                               #real one
                               if ($server -eq $env:COMPUTERNAME) 
                               #testing
                               #if ($server -eq "totot") 
                               {
                                    
                                    
                                    
                                        foreach($WebSite in $(get-website))

                                        {
                                            #($Website.logFile.directory)
                                            $logFilefolder="$($Website.logFile.directory)\W3SVC$($website.id)".replace("%SystemDrive%",$env:SystemDrive)
                                            $website.name;
                                            #testing
                                            $files = get-childItem -Path $logFilefolder -Recurse -Filter "*$IISdate*.log" 
                                            $files.Count
                                                                                      
                                            if((Test-Path -Path $logFilefolder) -and ($files.count -gt 0)){
                                            
                                            #retrive the folder represented by the IIS site ID 
                                            $folder =Split-Path -Path $logFilefolder -Leaf
                                            $folder

                                            #create the destination folder 

                                            $destf = ("{0}\{1}_{2}\{3}" -f $EventsDir, "IIS", $server, $folder)
                                            
                                            
                                            
                                            New-Item -Path $destf -Force -ItemType:directory
                                            $destf;
                                            

                                            # copy all the files matching the willcard in $IISdate
                                            if($destf){
                                            foreach($fichier in $files.FullName){
                                            
                                            # previous but with bug due to multiple copies in second execution 
                                            #Copy-Item -Path $logFilefolder -Filter "*$IISdate*.log" -Destination ("{0}\{1}_{2}\{3}" -f $EventsDir, "IIS", $server, $folder) -Force -Container: $false;
                                            
                                            Copy-Item $fichier -Destination $destf -Force -Container:$false;

                                            }
                                            }

                                            $h.ForegroundColor="green";
                                            Write-Host(" ... end " + $website.name);
                                            $h.ForegroundColor="gray";
                                            }
                                            else{"no entries for this IIS site " + $website.name}
  
                                        } 

                                    
                                    
                                    

                               }
                               else
                               {
                                    # this part should be change to invoke-command -ComputerName wfm -ScriptBlock {get-website} but we need to validate the remote powershell 
                                    $Session = New-PSSession -ComputerName $server

                                    $block = { 
                                        Import-Module 'webAdministration'
                                        get-website
                                    }

                                    $rsites =Invoke-Command -Session $Session -ErrorAction SilentlyContinue -ScriptBlock $block;    

                                    $rsites  |select name
                                    
                                    foreach($WebSite in $rsites)

                                        {
                                            #($Website.logFile.directory)
                                           

                                            # to be handled later if we are running the script APP servers where IIS sites are not existing we will not get the expected logs !!
                                            # for now the script need to be run in server with WFE role

                                            $logFilefolder="$($Website.logFile.directory)\W3SVC$($website.id)".replace("%SystemDrive%",$env:SystemDrive)
                                            $logFilefolder
                                            #testing
                                            $files = get-childItem -Path $logFilefolder -Recurse -Filter "*$IISdate*.log" 
                                            $files.Count
                                            
											# we need to test the network path not local path todo ==> 
											
                                            if((Test-Path -Path $logFilefolder) -and ($files.count -gt 0)){
                                            
                                            $netfolder = Split-Path -Path $logFilefolder -noQualifier

                                            $folder =Split-Path -Path $logFilefolder -Leaf
                                            $folder
                                            
                                            

                                            $destpath = ("\\" + ($server + "\C$" + $netfolder));
                                            $destpath
                                            Test-Path -Path $destpath
                                            try{
                                            if(Test-Path -Path $destpath){


                                            #Copy-Item -Path $destpath -Recurse -Filter "*$IISdate*.log" -Destination ("{0}\{1}_{2}\{3}" -f $EventsDir, "IIS", $server, $folder) -Force -Container: $false;
                                            foreach($fichier in $files){
                                            
                                            # previous but with bug due to multiple copies in second execution 
                                            #Copy-Item -Path $logFilefolder -Filter "*$IISdate*.log" -Destination ("{0}\{1}_{2}\{3}" -f $EventsDir, "IIS", $server, $folder) -Force -Container: $false;
                                            
                                            Copy-Item $fichier.FullName -Destination $destpath -Force -Container:$false;

                                            }
                                            
                                            
                                            }
                                            
                                            
                                            else{}
                                            }
                                            catch{}
                                            Start-Sleep 2;

                                            $h.ForegroundColor="green";
                                            Write-Host( " ... end " + ($WebSite.name).ToString());
                                            $h.ForegroundColor="gray";
                                            }
                                            else{"no entries for this IIS site " + $website.name}
  
                                        } ;                                    
                                    
                                    
                                    
                                    
                                    
                                    
                                    
                                    $h.ForegroundColor="green";
                                    Write-Host " ... end server $server";
                                    $h.ForegroundColor="gray";
                               }
                }
                catch 
                {
                               $h.ForegroundColor="red"
                               throw "[GetIISlogs][$server] (Ligne $($_.InvocationInfo.ScriptLineNumber)) $_"
                }
                
}

function GetMergedUlsLOgs(){

    $stime = $ULSstarttime -as [DateTime];
    $etime = $ULSendtime -as [DateTime];
    $mtime= get-date -Format d_M_HH_mm_ss
    
    Try{
                Merge-SPLogFile -Path "$EventsDir\FarmMergedLog_$mtime.log" -Overwrite -starttime ($stime).tostring() -endtime ($etime).tostring() 
                }
    catch {
                $h.ForegroundColor="red"
                throw "$Error[0].Exception.Message"
                Write-Host("check the date format ... ") 
	}
    




}

#################################################
#


$srvs=$null;
$srvs

if(!$servers){

    $srvs= Get-SPServer | ?{$_.role -ne "Invalid"};
    $srvs;
}
else{

    $srvs = $servers.split(',');
    $srvs;

}
    

#read-host

foreach($server in $srvs){

        $server;
        $server

         try
            {
            
            
                if($NoEvents -eq $false){
                    # Application Event viewer
                    $events=GetEventsLogsApplication -server $server -credential $credential
                    [string]$src01 = ("\\{0}\{1}" -f $server, $events.Name) -replace ":\\", "$\"
                    $h.ForegroundColor="gray"
                    $src01
                    Copy-Item -Path $src01 -Destination ("{0}\{1}_{2}.evtx" -f $EventsDir, "Application", $server) -Force
            
                    # System Event viewer
                    $events = GetEventsLogsSystem -server $server -credential $credential
                    $h.ForegroundColor="gray"
                    [string]$src02 = ("\\{0}\{1}" -f $server, $events.Name) -replace ":\\", "$\"
                    $src02
                    Copy-Item -Path $src02 -Destination ("{0}\{1}_{2}.evtx" -f $EventsDir, "System",$server) -Force
                }
            
               # IIS logs
                if($IISdate -ne $null){
                GetIISlogs -server $server -credential $credential
                }
                else{}
            
          }
          catch{throw "$Error[0].Exception.Message"}
	  

}

function mdb{$Error.Clear()}

# Merge ULS logs	
  
if($ULSstarttime -and $ULSendtime){

        GetMergedUlsLOgs;
        
 }

	
$h.BackgroundColor="black";
$h.ForegroundColor="white";   

Write-Host "script ended...";

         
     
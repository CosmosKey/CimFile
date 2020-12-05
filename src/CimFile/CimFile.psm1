function Get-CimEscapedPath {
    param(
        [string]$Path
    )
    $Path -replace [regex]::Escape('\') ,'\\'
}

function Add-PSType {
    param(
        [parameter(ValueFromPipeline,Mandatory)]
        $InputObject,
        [Parameter(Mandatory)]
        [string]$TypeName,
        [switch]$Passthru
    )
    process {
        if($null -ne $InputObject) {
            if( -not $InputObject.pstypenames.Contains($TypeName)) {
                $InputObject.pstypenames.Insert(0,$TypeName)
            }
            if($Passthru) {
                $InputObject
            }
        }

    }
}

<#
.SYNOPSIS

    Gets the files and folders using CIM.

.DESCRIPTION

    The Get-CimFile cmdlet gets the files and folders in one or more specified locations. If the path specified is a folder, it gets the files and folders inside the container.

.PARAMETER Path

    Specifies a path to one or more folder or files. Wildcards are permitted. The default location is the current directory (.).

.PARAMETER Filter

    Specifies a file search wildcard filter.

.PARAMETER Recurse

    Indicates that this cmdlet gets the files and folders in the specified locations and in all child folders of the locations.

.PARAMETER File

    Gets only files.

.PARAMETER Directory

    Gets only directories.

.PARAMETER CimSession

    Specifies the CIM session to use for this cmdlet. Enter a variable that contains the CIM session or a command that creates or gets the CIM session, such as the New-CimSession or Get-CimSession cmdlets. For more information, see about_CimSessions.

.EXAMPLE

    Get-CimFile -Path $home

    Gets all the files and folders in the home directory

.EXAMPLE

    ${env:ProgramFiles(x86)},$env:ProgramFiles | Get-CimFile -Filter *Microsoft* -Directory

    List all folders containing the string 'Microsoft' in both the 32-bit and 64-bit program files folders 

.EXAMPLE
    
    PS C:\>$cimSession = New-CimSession -ComputerName SRV01
    PS C:\>Get-CimFile -CimSession $cimSession -Path c:\Users -Directory

    Gets all the folders in the C:\Users folder on server SRV01

.EXAMPLE

    "$home\OneDrive" | Get-CimFile -Filter *.ps1 -Recurse -File

    This will list all the *.ps1 files in the users OneDrive folder.
    
#>

function Get-CimFile
{
    [cmdletbinding(DefaultParameterSetName='FilesOnly', PositionalBinding)]
    param(
        [parameter( Position = 1, ValueFromPipeline )]
        [string[]]$Path = $PWD.Path,        
        [SupportsWildcards()]
        [parameter( Position = 2 )]
        [string]$Filter = '*',
        [switch]$Recurse,
        [Parameter( ParameterSetName = 'DirectoriesOnly' )]
        [switch]$Directory,
        [Parameter( ParameterSetName = 'FilesOnly' )]
        [switch]$File,
        [parameter( Position = 3)]
        [CimSession]$CimSession
    )
    begin {
        $cimSessionParam = @{}
        if($PSBoundParameters.ContainsKey('CimSession')) {
            $cimSessionParam['CimSession'] = $PSBoundParameters['CimSession']
        }
    }
    process {
        foreach($_path in $Path) {
            Write-Verbose "Querying CIM for path: $_path and filter $Filter. Parameter -File is $File, -Directory is $Directory and CimSession $CimSession "
            $_path = $_path.Trim()
            if( [WildcardPattern]::ContainsWildcardCharacters($_path) ) { 
                $li = $_path.LastIndexOf('\')
                switch($li) {
                    -1 { $Filter = $_Path; $_path = '.\'}
                    0  { $Filter = $_path.Substring(1); $_path='\'}
                    default {
                        $Filter = $_path.Substring($li+1)
                        $_path = $_path.Substring(0,$li) + '\'
                    }
                }
            }

            $filepath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($pwd.Path,$_path))                 
            if($filepath -notlike '*\') {
                $fileObj = Get-CimInstance -ClassName CIM_LogicalFile -Filter ("Name = '{0}'" -f (Get-CimEscapedPath $filepath) ) 
                if($fileObj.Count -eq 1 -and $fileObj.CimClass.CimClassName -eq 'CIM_Datafile') {
                    $fileObj | Add-PSType -TypeName 'CIMFile' -Passthru 
                    return
                } else {
                    $filepath+='\'
                }
            }
            $drive,$remainderPath = $filepath.Split(':')
            
            $likeFilter = ([WildcardPattern]$Filter).ToWql().Trim()   
            $cimFilter        = "drive = '{0}:' and path ='{1}' and name like '{0}:{1}{2}' " -f $drive,(Get-CimEscapedPath $remainderPath),$likeFilter
            $cimRecurseFilter = "drive = '{0}:' and path ='{1}' "                            -f $drive,(Get-CimEscapedPath $remainderPath)
            
            if($Recurse) {                
                foreach($folder in Get-CimInstance -ClassName WIN32_Directory -Filter $cimRecurseFilter @cimSessionParam) {
                    $PSBoundParameters['Path'] = Join-Path $_path $folder.FileName
                    $PSBoundParameters['Filter'] = $Filter
                    & $MyInvocation.MyCommand @PSBoundParameters
                }
            }
            if( -not $File) {
                Get-CimInstance -ClassName WIN32_Directory -Filter $cimFilter @cimSessionParam | Add-PSType -TypeName 'CIMFolder' -Passthru
            }
            if( -not $Directory) {
                Get-CimInstance -ClassName CIM_Datafile    -Filter $cimFilter @cimSessionParam | Add-PSType -TypeName 'CIMFile'   -Passthru
            }
        }
    }
}

function Out-Default {
    [CmdletBinding(HelpUri='https://go.microsoft.com/fwlink/?LinkID=113362', RemotingCapability='None')]
    param(
        [switch]
        ${Transcript},

        [Parameter(ValueFromPipeline=$true)]
        [psobject]
        ${InputObject})

    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Core\Out-Default', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
            $steppablePipeline.Begin($PSCmdlet)

            $sb = { Out-String -Stream } 
            $sbSteppable = $sb.GetSteppablePipeline()
            $sbSteppable.Begin($true)

        } catch {
            throw
        }
        $managedLastExecuted = $false
    }

    process
    {
        try {
            if($_.pstypenames.contains('CIMFolder') -or $_.pstypenames.contains('CIMFile')) {
                $managedLastExecuted = $true
                $foregroundParam = @{}
                if($_.Compressed) {$foregroundParam.ForegroundColor = 'Yellow'}
                if($_.hidden    ) {$foregroundParam.ForegroundColor = 'Gray'}
                if($_.Encrypted ) {$foregroundParam.ForegroundColor = 'Green'}
                if($_.system    ) {$foregroundParam.ForegroundColor = 'DarkCyan'}
                [array]$res = $sbSteppable.Process($InputObject)
                for($i=0; $i -lt $res.count; $i++) {
                    if($i -eq ($res.count -1)) {
                        Write-Host $res[$i] @foregroundParam 
                    } else {
                        Write-Host $res[$i] 
                    }
                }
            } else {
                $steppablePipeline.Process($_)
                $managedLastExecuted = $false
            }
        } catch {
            throw
        }
    }

    end
    {
        try {
            if($managedLastExecuted) {
                $sbSteppable.End()
            } else {
                $steppablePipeline.End()
            }
        } catch {
            throw
        }
    }
    <#

    .ForwardHelpTargetName Microsoft.PowerShell.Core\Out-Default
    .ForwardHelpCategory Cmdlet

    #>

}

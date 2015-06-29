param($installPath, $toolsPath, $package, $project)

@"
===========================================================
        Ultimate Cross Platform NuGet Restore
===========================================================
This package automates the creation of the best approach 
to managing package restore, as suggested by the NuGet 
team themselves: it does NOT use the deprecated, old 
and viral NuGet.targets file, running restore only when
executed from a command line using MSBuild or XBuild, 
and NEVER when building from Visual Studio or Xamarin 
Studio, which manage the restore automatically already.

This makes for faster builds inside and outside of the IDE.

This package creates the following two files at your 
solution root directory:

  - Before.[your_solution_file_name].targets: imported and 
    run automatically by MSBuild and XBuild for command 
    line builds, which imports the next file:
  - NuGet.Restore.targets: contains the actual logic for 
    restoring packages.

Further solutions can automatically be restore by just 
copying and renaming the Before.[sln_file_name].targets 
alongise them. The import of NuGet.Restore.targets is 
resilient to the actual solution location, so it can 
exist anywhere as long as the NuGet.Restore.targets file 
can be located in an ancestor folder.

Once the copying is done, this package uninstalls itself.
===========================================================
"@ | Write-Host

    $solution = $dte.Solution.FullName
    $solutionDir = [System.IO.Path]::GetDirectoryName($solution)
    $target = $solutionDir + "\Before." + [System.IO.Path]::GetFileName($solution) + ".targets"
    if (!(Test-Path $target))
    {
        Copy-Item "$toolsPath\Before.Blank.sln.targets" -Destination $target
        Write-Host Created $target
    }
    else
    {
        Write-Host Found existing solution targets at $target
    }

    $current = (Get-Item $solutionDir)
    $found = $false
    while (![string]::IsNullOrWhiteSpace($current))
    {
        $file = Join-Path $current.FullName NuGet.Restore.targets
        if (Test-Path $file)
        {
            $found = $true
            break
        }

        $current = $current.Parent
    }

    if ($found) 
    {
        $file = (Join-Path $current.FullName NuGet.Restore.targets)
        Copy-Item "$toolsPath\NuGet.Restore.targets" -Force -Destination $file
        Write-Host Updated $file
    }
    else
    {
        Copy-Item "$toolsPath\NuGet.Restore.targets" -Destination $solutionDir
        Write-Host Created $solutionDir\NuGet.Restore.targets
    }
    
    # We're done copying, we can go away now.
    Uninstall-Package NuGet.Restore
    
    Write-Host "Work done. NuGet.Restore has uninstalled itself :-). Enjoy!"
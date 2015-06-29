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

This package has created the following two files at your 
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
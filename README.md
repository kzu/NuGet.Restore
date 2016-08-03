![Icon](https://raw.githubusercontent.com/kzu/NuGet.Restore/master/icon.png) Ultimate Cross Platform NuGet Restore
============

This project provides the best-practice, NuGet-team blessed, most reliable and performant way 
of performing automatic NuGet package restore across MSBuild and XBuild, without causing unnecessary 
extra restores from Visual Studio and Xamarin Studio, which handle the restore already by themselves.

Now that 'Enable NuGet Package Restore' is the deprecated non-recommended way of doing package 
restores, everyone is coming up with a different way of doing it in a way that works on build 
servers and command line builds. Here is an approach that follows NuGet's own guidance but also 
works from command line MSBuild, build servers, Linux/Mac via Mono's xbuild and even Xamarin 
Studio. Oh, and it requires NO tuning of your build process, you just continue to build your 
solution files as usual.
 
This new approach leverages the built-in support in MSBuild and XBuild for solution-level 
MSBuild imports so that restoring packages is done only ONCE for an entire solution, and it's 
NOT used when doing IDE builds.

## Usage

1. Download [the targets file](https://raw.githubusercontent.com/kzu/NuGet.Restore/master/NuGet.Restore.targets "Targets file for automated restore") 
   alongside your .sln or on an ancestor folder 
   (you can also `curl -f -k -L -o NuGet.Restore.targets http://bit.ly/nugetore` instead)
2. Run `msbuild NuGet.Restore.targets /t:Init`: this will traverse all 
   directories from the path where you placed the targets file, looking 
   for all *.sln that don't have a correspondig `Before.[sln].targets`
   and create one automatically, enabling command-line build automated 
   solution restore for them.
3. You can stay up to date with changes to the target by running 
   `msbuild NuGet.Restore.targets /t:Update`. It's recommended you run 
   on first use too, since that updates the `ETag` used for subsequent 
   checks.

That's it. Now either MSBuild or XBuild command line builds of any 
solution file in your repository will automatically perform a solution 
restore before opening the projects and performing the build.

If you want to learn how it works in more detail, keep reading :).

## Overview

Back in the day, when NuGet just came out, you were supposed to just right-click on your 
solution node in Visual Studio, and click "Enable NuGet Package Restore". You may be surprised 
to still find that context menu command even when the 
[latest recommendation](http://docs.nuget.org/docs/reference/package-restore "Package Restore Documentation") 
by the NuGet team is to NOT use it. 

The new way is to just run nuget.exe restore before building the solution. And of course 
there are a gazillion ways of doing it, from batch files, to a 
[separate MSBuild file](http://chris.eldredge.io/blog/2014/01/29/the-newer-new-nuget-package-restore/) 
that is built instead of the main solution, to powershell scripts, etc. Oh, and you should 
probably download nuget.exe from nuget.org too before doing the restore ;).

With the unstoppable rise of Xamarin for development (ok, maybe I'm slightly biased ;)), 
it's highly desirable that whatever solution you adopt also works on a Mac too, Xamarin Studio, 
and why not xbuild in addition to MSBuild command line builds?

It turns out that such a cross-platform solution is pretty straight-forward to implement 
and fairly simple, by just leveraging a little-known extensibility hook in MSBuild/xbuild. 


## IDE vs Command Line Builds

Both Xamarin Studio and Visual Studio build solutions differently than their command line 
counterparts xbuild and MSBuild. Both IDEs read the solution file and construct their 
in-memory representations of the included projects. From that point on, it's the IDE that 
controls the build, not the command-line xbuild/msbuildn tools. 

But since the solution file is not an MSBuild file, on command line builds a 
[temporary MSBuild file is created from the solution](http://sedodream.com/2010/10/22/MSBuildExtendingTheSolutionBuild.aspx), 
and this file is built instead. And luckily, it also has some extensibility points itself 
that we can leverage.

It's important to keep in mind though that these extensibility points are for the command 
line builds only, which is a really nice plus in this case, since both IDEs already do 
their own NuGet package restore automatically (and that's why the project-level MSBuild-based 
package restore from before is no longer recommended, it's just duplicate behavior that 
basically slows down every build).

> NOTE: this does not change with the new NuGet v3, since solution-level restores before 
> build are still not supported out of the box.

So, part of the good news is: if you just want IDE-driven NuGet package restore, you 
don't have to do anything at all :). But who does IDE-only builds these days anyway? 
So let's see how we tweak the command line builds so that they work from the very same 
solution file as the IDE, AND, without involving *any* changes to build/CI scripts that 
you may currently have. The solution is fully unobtrusive, and at most, allows you to
*removing* the parts of your build/CI scripts that did the solution-level restore 
manually previously.

##  Command Line Automated Package Restore

The approach is to basically have a file named Before.[solution file name].targets 
(like Before.MyApp.sln.targets) alongside the solution. As 
[explained by the awesome Sayed in his blog](http://sedodream.com/2010/10/22/MSBuildExtendingTheSolutionBuild.aspx "Extending the solution build"), 
this targets file is imported alongside the temporary MSBuild project generated for 
the solution, and can therefore provide targets that run before/after any of the 
built-in ones it contains:

- Build
- Rebuild
- Clean
- Publish

For package restore, we'll just provide a target that runs before Build.

The gist of the solution is very very simple:


	<PropertyGroup>
		<NuGetPath Condition=" '$(NuGetPath)' == '' ">$(MSBuildThisFileDirectory).nuget</NuGetPath>
		<NuGetUrl Condition=" '$(NuGetUrl)' == '' ">https://dist.nuget.org/win-x86-commandline/latest/nuget.exe</NuGetUrl>
		<NuGet Condition=" '$(NuGet)' == '' ">$(NuGetPath)\nuget.exe</NuGet>
		<Mono Condition=" '$(OS)' != 'Windows_NT' ">mono</Mono>
	</PropertyGroup>

	<Target Name="RestorePackages" 
			BeforeTargets="Build" 
			DependsOnTargets="DownloadNuGet;EnsureBeforeSolutionImport;RestoreSolutions"
			Condition=" '$(RestorePackages)' != 'false' " />

The `DownloadNuGet` target takes care of automatically downloading the `nuget.exe` command line
from the official URL. 
The `EnsureBeforeSolutionImport` will just error if you try to import this targets file from 
anything but the `Before.[sln].targets` file, just to avoid misuse.
Finally, the `RestoreSolutions` target basically does the following:

	<Exec Command='$(Mono) "$(NuGet)" Restore "$(SolutionPath)"'
			WorkingDirectory="$(RestoreDir)" />


> NOTE: `$(Mono)` will be empty on Windows

In order to download files, we use `curl` both on the Mac and Windows. If it's not available, 
we download it from [this same repository](https://github.com/kzu/NuGet.Restore/master/curl.exe) 
using PowerShell on Windows. 

	<Target Name="DownloadCurl" Condition=" '$(OS)' == 'Windows_NT' And !Exists('$(TEMP)\curl.exe') ">
		<PropertyGroup>
			<PowerShell Condition=" '$(PowerShell)' == '' ">%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe</PowerShell>
		</PropertyGroup>

		<Exec Command="&quot;$(PowerShell)&quot; -NoProfile -Command &quot;&amp; { (New-Object System.Net.WebClient).DownloadFile('$(CurlUrl)', '$(TEMP)\curl.exe') }&quot;" />
	</Target>

With `curl` at hand, it's trivial to download `nuget.exe` before the other targets:

	<Target Name="DownloadNuGet" DependsOnTargets="DownloadCurl" Condition=" !Exists('$(NuGet)') ">
		<MakeDir Directories="$(NuGetPath)" Condition=" !Exists('$(NuGetPath)') " />
		<Exec Command='$(Curl) -o "$(NuGet)" "$(NuGetUrl)"' />
	</Target>

For restoring the solution, the targets simply add the current solution to the `@(RestoreSolution)`
item group:

	<ItemGroup>
		<RestoreSolution Include="$(SolutionPath)" Condition=" '$(SolutionPath)' != '' " />
	</ItemGroup>

Note that being an item group, it allows adding more solutions to restore. It might be that a 
given solution brings in projects from other solutions, that may have their nuget packages 
installed to a different folder than your solution root. In those cases, you should be restoring 
those external solutions too before building yours. This can easily be achieved by customizing the 
`Before.[sln].targets` you got. For example:

	<ItemGroup>
		<!-- Restore/Install some packages that are used without any version # in the path -->
		<RestoreSolution Include="$(BuildDir)packages.config">
			<Command>Install</Command>
			<!-- We can pass arbitrary arguments to nuget.exe this way -->
			<Args>-ExcludeVersion</Args>
			<OutputDirectory>$(RootDir).nuget\packages</OutputDirectory>
		</RestoreSolution>

		<!-- Restore a submodule solution -->
		<RestoreSolution Include="$(ExternalDir)SomeSubmodule\SomeSubmodule.sln">
			<!-- Rather than installing the packages to the default path relative 
				 to the current solution, make them relative to the submodule path
			-->
			<OutputDirectory>$(ExternalDir)SomeSubmodule\packages</OutputDirectory>
		</RestoreSolution>
	</ItemGroup>

These advanced capabilities are generally not necessary, but for more complex solutions 
with external dependencies consumed as source code (project references), it's pretty 
useful. We use this mechanism in *Xamarin for Visual Studio*, for example.



So there it goes: a single .targets file, and you can do IDE and command line builds 
consistently that automatically restore without slowing down builds for each project 
unnecessarily.

You can just [inspect the entire targets file](https://github.com/kzu/master/NuGet.Restore.targets "Targets file for automated restore") 
to learn more, since there are no compiled tasks or external dependencies whatsoever.



Happy nugetting! ;)

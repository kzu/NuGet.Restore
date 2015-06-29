![Icon](https://raw.github.com/kzu/NuGetRestore/master/img/icon.png) Ultimate Cross Platform NuGet Restore
============

Provides the best-practice, NuGet-team blessed, most reliable and performant way of performing 
automatic NuGet package restore across MSBuild and XBuild, without causing unnecessary extra 
restores from Visual Studio and Xamarin Studio, which handle the restore already by themselves.

Now that 'Enable NuGet Package Restore' is the deprecated non-recommended way of doing package 
restores, everyone is coming up with a different way of doing it in a way that works on build 
servers and command line builds. Here is an approach that follows NuGet's own guidance but also 
works from command line MSBuild, build servers, Linux/Mac via Mono's xbuild and even Xamarin 
Studio. Oh, and it requires NO tuning of your build process, you just continue to build your 
solution files as usual.
 
This new approach leverages the built-in support in MSBuild and XBuild for solution-level 
MSBuild imports so that restoring packages is done only ONCE for an entire solution, and it's 
NOT used when doing IDE builds.

## Overview

> If you just want the straight solution, [download the targets file](https://raw.githubusercontent.com/kzu/kzu.github.io/master/code/AutoRestore/Before.MyApp.sln.targets "Targets file for automated restore") alongside your .sln and name it `Before.[solution file name].targets`. Now just build from either IDEs or command lines :).

Back in the day, when NuGet just came out, you were supposed to just right-click on your solution node in Visual Studio, and click "Enable NuGet Package Restore". You may be surprised to still find that context menu command even when the [latest recommendation](http://docs.nuget.org/docs/reference/package-restore "Package Restore Documentation") by the NuGet team is to NOT use it. 

The new way is to just run nuget.exe restore before building the solution. And of course there are a gazillion ways of doing it, from batch files, to a [separate MSBuild file](http://chris.eldredge.io/blog/2014/01/29/the-newer-new-nuget-package-restore/) that is built instead of the main solution, to powershell scripts, etc. Oh, and you should probably download nuget.exe from nuget.org too before doing the restore ;).

With the unstoppable rise of Xamarin for development (ok, maybe I'm slightly biased ;)), it's highly desirable that whatever solution you adopt also works on a Mac too, Xamarin Studio, and why not xbuild in addition to MSBuild command line builds?

It turns out that such a cross-platform solution is pretty straight-forward to implement and very simple, by just leveraging a little-known extensibility hook in MSBuild/xbuild. 


## IDE vs Command Line Builds

Both Xamarin Studio and Visual Studio build solutions differently than their command line counterparts xbuild and MSBuild. Both IDEs read the solution file and construct their in-memory representations of the included projects. From that point on, it's the IDE that controls the build, not the command-line xbuild/msbuildn tools. 

But since the solution file is not an MSBuild file, on command line builds a [temporary MSBuild file is created from the solution](http://sedodream.com/2010/10/22/MSBuildExtendingTheSolutionBuild.aspx), and this file is built instead. And luckily, it also has some extensibility points itself that we can leverage.

It's important to keep in mind though that these extensibility points are for the command line builds only, which is a really nice plus in this case, since both IDEs already do their own NuGet package restore automatically (and that's why the project-level MSBuild-based package restore from before is no longer recommended, it's just duplicate behavior that just slows down every build).

So, part of the good news is: if you just want IDE-driven NuGet package restore, you don't have to do anything at all :). But who does IDE-only builds these days anyway? So let's see how we tweak the command line builds so that they work from the very same solution file as the IDE.

##  Command Line Automated Package Restore

The approach is to basically have a file named Before.[solution file name].targets (like Before.MyApp.sln.targets) alongside the solution. As [explained by the awesome Sayed in his blog](http://sedodream.com/2010/10/22/MSBuildExtendingTheSolutionBuild.aspx "Extending the solution build"), this targets file is imported alongside the temporary MSBuild project generated for the solution, and can therefore provide targets that run before/after any of the built-in ones it contains:

- Build
- Rebuild
- Clean
- Publish

For package restore, we'll just provide a target that runs before Build. On a Mac, if Xamarin Studio is installed and you're performing a command line build, the "nuget" (no ".exe" extension) command will already be available in the path, so we need to conditionally do things slightly different there than on Windows.

The gist of the solution is very very simple:


	<PropertyGroup>
		<NuGetExe Condition="'$(OS)' == 'Windows_NT'">.nuget\NuGet.exe</NuGetExe>
		<NuGetExe Condition="'$(OS)' != 'Windows_NT'">nuget</NuGetExe>
	</PropertyGroup>

	<Target Name="RestorePackages" 
			BeforeTargets="Build" 
			DependsOnTargets="DownloadNuGet">
		<Exec Command="&quot;$(NuGetExe)&quot; Restore &quot;$(SolutionPath)&quot;" />
	</Target>


That's basically it. Run `NuGet.exe Restore [solution]` on Windows, and `nuget Restore [solution]` otherwise. Of course, on Windows we'll also need to download the nuget executable if we don't find it locally, so that's the DownloadNuGet target. This target just uses an inline code task that downloads the executable from nuget.org, just like the now deprecated NuGet.targets restore did, with a tweak to make it work consistently across all installed versions of MSBuild/Visual Studio.


Note that this target will never run on the Mac/xbuild. And it's important since xbuild does not support [inline code tasks](http://msdn.microsoft.com/en-us/library/dd722601.aspx "MSBuild Inline Tasks on MSDN"). 

	<Target Name="DownloadNuGet" Condition="'$(OS)' == 'Windows_NT' And !Exists('$(NuGetExe)')">
		<DownloadNuGet TargetPath="$(NuGetExe)" />
	</Target>

	<UsingTask TaskName="DownloadNuGet" TaskFactory="CodeTaskFactory" AssemblyFile="$(CodeTaskAssembly)">
		<ParameterGroup>
			<TargetPath ParameterType="System.String" Required="true" />
		</ParameterGroup>
		<Task>
			<Reference Include="System.Core" />
			<Using Namespace="System" />
			<Using Namespace="System.IO" />
			<Using Namespace="System.Net" />
			<Using Namespace="Microsoft.Build.Framework" />
			<Using Namespace="Microsoft.Build.Utilities" />
			<Code Type="Fragment" Language="cs">
				<![CDATA[
                try {
                    TargetPath = Path.GetFullPath(TargetPath);
                    if (!Directory.Exists(Path.GetDirectoryName(TargetPath)))
                        Directory.CreateDirectory(Path.GetDirectoryName(TargetPath));

                    Log.LogMessage("Downloading latest version of NuGet.exe...");
                    WebClient webClient = new WebClient();
                    webClient.DownloadFile("https://www.nuget.org/nuget.exe", TargetPath);

                    return true;
                }
                catch (Exception ex) {
                    Log.LogErrorFromException(ex);
                    return false;
                }
            ]]>
			</Code>
		</Task>
	</UsingTask>

The situation with MSBuild inline code tasks is quite a mess with regards to the CodeTaskFactory assembly name. Between MSBuild 4 (VS2010), MSBuild 12 (VS2013) and MSBuild 14 (VS2015), Microsoft changed not only the location of the file but also its name, in *each* version. So there are *three* ways of pointing to the right assembly. Sigh. 

Anyway, this solution I found seems to be the most consistent with the way Microsoft itself detects what version of VS/MSBuild is running and what assemblies should be used:

	<PropertyGroup Condition="'$(OS)' == 'Windows_NT'">
		<CodeTaskAssembly Condition="'$(MSBuildAssemblyVersion)' == ''">$(MSBuildToolsPath)\Microsoft.Build.Tasks.v4.0.dll</CodeTaskAssembly>
		<!-- In VS2013, the assembly contains the VS version. -->
		<CodeTaskAssembly Condition="'$(MSBuildAssemblyVersion)' == '12.0'">$(MSBuildToolsPath)\Microsoft.Build.Tasks.v12.0.dll</CodeTaskAssembly>
		<!-- In VS2015+, the assembly was renamed, hopefully this will be the last condition! -->
		<CodeTaskAssembly Condition="'$(MSBuildAssemblyVersion)' != '' and '$(MSBuildAssemblyVersion)' &gt;= '14.0'">$(MSBuildToolsPath)\Microsoft.Build.Tasks.Core.dll</CodeTaskAssembly>
	</PropertyGroup>

Again, this is something that only applies to Windows/MSBuild, not Mac/xbuild. The condition isn't really necessary, but it just makes it clearer that this applies only to Windows/MSBuild. `MSBuildAssemblyVersion` is a new reserved property (since MSBuild 12) that allows us to determine the right assembly to specify for the CodeTaskFactory task.


So there it goes: a simple .targets file alongside the solution file, and you can do IDE and command line builds consistently that automatically restore without slowing down builds for each project unnecessarily.

You can just [download the entire targets file](https://raw.githubusercontent.com/kzu/kzu.github.io/master/code/AutoRestore/Before.MyApp.sln.targets "Targets file for automated restore") alongside your .sln and name it `Before.[solution file name].targets`.

## NuGet-ized

To make this even easier, this repository provides a [nuget package](https://www.nuget.org/packages/NuGet.Restore). In your repository root, just run:

    NuGet Install NuGet.Restore -ExcludeVersion

This will install the package without the version suffix, so that you can safely reference the included `nuget.targets` files from your solution targets. The package contains a sample solution targets file that you can copy and rename alongside your solutions, adjusting the relative path to the `nuget.targets` import that does the actual 'magic'.  



Happy nugetting! ;)
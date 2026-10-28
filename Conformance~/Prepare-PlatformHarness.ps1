param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$ProjectionRoot
)
$ErrorActionPreference='Stop'
$wrapper=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target=[IO.Path]::GetFullPath($Destination)
if ((Test-Path -LiteralPath $target) -or $target.StartsWith($wrapper+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Platform harness must be new and outside the source checkout.'
}
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item -LiteralPath (Join-Path $wrapper 'UnityImplementation/WssTransportSupport.cs') -Destination $target
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PlatformCompatibility.cs') -Destination $target
New-Item -ItemType Directory -Path (Join-Path $target 'payload') | Out-Null
Copy-Item -Path (Join-Path $ProjectionRoot '*') -Destination (Join-Path $target 'payload') -Recurse
$project=@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>disable</Nullable>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <UseAppHost>false</UseAppHost>
  </PropertyGroup>
  <PropertyGroup Condition="$([MSBuild]::IsOSPlatform('Windows'))">
    <DefineConstants>$(DefineConstants);UNITY_STANDALONE_WIN</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="$([MSBuild]::IsOSPlatform('Linux'))">
    <DefineConstants>$(DefineConstants);UNITY_STANDALONE_LINUX</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="$([MSBuild]::IsOSPlatform('OSX'))">
    <DefineConstants>$(DefineConstants);UNITY_STANDALONE_OSX</DefineConstants>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="*.cs" />
    <!-- Match the C# host's .NET runtime selection metadata. Runtime bytes are
         independently checked against the exact projected candidate below. -->
    <PackageReference Include="System.IO.Ports" Version="8.0.0" />
    <Reference Include="payload/*.dll" Exclude="payload/WssBleWindows.dll;payload/System.IO.Ports.dll">
      <Private>false</Private>
    </Reference>
    <Content Include="payload/**/*" Exclude="payload/**/*.meta">
      <Link>%(RecursiveDir)%(Filename)%(Extension)</Link>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
      <CopyToPublishDirectory>PreserveNewest</CopyToPublishDirectory>
    </Content>
  </ItemGroup>
</Project>
'@
[IO.File]::WriteAllText((Join-Path $target 'Wss.PlatformCompatibility.csproj'),$project)
@{sdk=@{version='9.0.316';rollForward='disable'}} | ConvertTo-Json | Set-Content (Join-Path $target 'global.json')
Write-Output "Prepared production transport selector .NET load-only probe at $target"

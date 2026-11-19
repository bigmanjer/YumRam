#requires -Version 5.1
<#
Static scan for Windows PowerShell 5.1 pitfalls that each caused a real YUMRAM bug.
Uses the PowerShell AST, so comments and strings that merely mention a pattern do not trigger it.

  Rule                     Real bug it caught
  -----------------------  -----------------------------------------------------------------------
  StatementAsCommand       -TopN (if(...){16}else{10}) ran a command named 'if'; every reclaim threw
  SingleQuotedEscape       'Line1`nLine2' showed a literal `n in ten dialogs
  FormatArgCount           'Research {0}/{1} - {2}' -f $a,$b threw FormatException
  ArrayArithmetic          -f $name,$id,$x/1MB divided an array (comma binds tighter than /)
  SortAscending            Sort-Object ... -Ascending (no such parameter) broke every trim plan
  TimersTimer              System.Timers.Timer scriptblock handlers never run on PS 5.1
  MandatoryNullableObject  [Parameter(Mandatory)]$Object rejects $null before the body runs
#>
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$findings=New-Object System.Collections.Generic.List[string]
function Add-Finding([string]$Rule,[string]$File,$Extent,[string]$Detail){
    $findings.Add(('{0}  {1}:{2}  {3}' -f $Rule,$File,$Extent.StartLineNumber,$Detail))
}
$A=[System.Management.Automation.Language.Ast]
$files=@(Get-ChildItem -LiteralPath (Join-Path $root 'App'),(Join-Path $root 'Core'),(Join-Path $root 'UI') -Filter *.ps1 -Recurse)
foreach($f in $files){
    $tokens=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
    $name=$f.FullName.Substring($root.Length+1)
    foreach($e in @($errors)){Add-Finding 'ParseError' $name $e.Extent $e.Message}

    foreach($n in $ast.FindAll({param($x) $x -is [System.Management.Automation.Language.CommandAst]},$true)){
        $cmd=$n.GetCommandName()
        if($cmd -in @('if','switch','foreach','for','while','do','try','trap')){Add-Finding 'StatementAsCommand' $name $n.Extent "'$cmd' used as a command; wrap the statement in `$( )"}
        if($cmd -eq 'Sort-Object'){
            foreach($p in @($n.CommandElements | Where-Object {$_ -is [System.Management.Automation.Language.CommandParameterAst]})){
                if($p.ParameterName -eq 'Ascending'){Add-Finding 'SortAscending' $name $n.Extent 'Sort-Object has no -Ascending parameter (ascending is the default)'}
            }
        }
        if($cmd -eq 'New-Object' -and $n.Extent.Text -match 'System\.Timers\.Timer'){Add-Finding 'TimersTimer' $name $n.Extent 'scriptblock handlers on System.Timers.Timer never run in PS 5.1; use a runspace worker or DispatcherTimer'}
    }

    foreach($n in $ast.FindAll({param($x) $x -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $x.StringConstantType -eq 'SingleQuoted' -and $x.Value -match '`[nrt0]'},$true)){
        # Allowed: strings passed to -match/-replace/-split, and the scanner's own rule text.
        $parent=$n.Parent
        if($parent -is [System.Management.Automation.Language.BinaryExpressionAst] -and $parent.Operator -in @('Imatch','Inotmatch','Ireplace','Isplit','Cmatch','Creplace','Ilike','Inotlike')){continue}
        Add-Finding 'SingleQuotedEscape' $name $n.Extent 'backtick escape inside single quotes is printed literally; use double quotes'
    }

    foreach($n in $ast.FindAll({param($x) $x -is [System.Management.Automation.Language.BinaryExpressionAst] -and $x.Operator -eq 'Format' -and $x.Left -is [System.Management.Automation.Language.StringConstantExpressionAst]},$true)){
        $fmt=($n.Left.Value -replace '\{\{|\}\}','')
        $idx=@([regex]::Matches($fmt,'\{(\d+)') | ForEach-Object {[int]$_.Groups[1].Value})
        if($idx.Count -eq 0){continue}
        $max=($idx | Measure-Object -Maximum).Maximum
        if($n.Right -is [System.Management.Automation.Language.ArrayLiteralAst]){
            if($n.Right.Elements.Count -le $max){Add-Finding 'FormatArgCount' $name $n.Extent ("format needs {0} arguments, has {1}" -f ($max+1),$n.Right.Elements.Count)}
        }
    }

    foreach($n in $ast.FindAll({param($x) $x -is [System.Management.Automation.Language.BinaryExpressionAst] -and $x.Left -is [System.Management.Automation.Language.ArrayLiteralAst] -and $x.Operator -in @('Divide','Multiply','Minus','Rem')},$true)){
        Add-Finding 'ArrayArithmetic' $name $n.Extent "'a,b/c' divides the array; parenthesize the element"
    }

    foreach($p in $ast.FindAll({param($x) $x -is [System.Management.Automation.Language.ParameterAst]},$true)){
        $mandatory=@($p.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' -and $_.Extent.Text -match 'Mandatory' }).Count -gt 0
        $allowNull=@($p.Attributes | Where-Object { $_.TypeName.Name -in @('AllowNull','AllowEmptyString','AllowEmptyCollection') }).Count -gt 0
        $untyped=@($p.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] }).Count -eq 0
        $fn=$p.Parent.Parent.Parent
        $fnName=if($fn -is [System.Management.Automation.Language.FunctionDefinitionAst]){$fn.Name}else{''}
        # Helpers whose job is to tolerate missing data must accept $null.
        if($mandatory -and -not $allowNull -and $untyped -and $p.Name.VariablePath.UserPath -eq 'Object' -and $fnName -match 'Safe'){
            Add-Finding 'MandatoryNullableObject' $name $p.Extent "$fnName rejects `$null for -Object; add [AllowNull()] and drop Mandatory"
        }
    }
}
if($findings.Count -gt 0){$findings | ForEach-Object {Write-Host "FAIL $_"}; exit 1}
Write-Output ('PASS: no PowerShell 5.1 pitfalls in {0} source files.' -f $files.Count)

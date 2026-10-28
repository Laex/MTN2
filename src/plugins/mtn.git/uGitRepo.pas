unit uGitRepo;

{ Finds the git working tree of a folder and runs "git status" in it through the
  platform's captured-process runner (hidden window on Windows, no input, a time
  limit). The caller's cancel function is polled so that unloading the plugin
  never waits for git. }

interface

uses
  System.SysUtils, uGitStatus;

type
  TGitReadResult = (grOk, grNotRepo, grError);

/// <summary>True when ADir or one of its parents holds a ".git" folder or file.</summary>
function IsInsideGitWorkTree(const ADir: string): Boolean;

/// <summary>Runs git status in ADir. grNotRepo = ADir is not in a working tree (or
/// git refused it); grError = git could not be run or ran too long.</summary>
function ReadGitStatus(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AStatus: TGitStatus): TGitReadResult;

implementation

uses
  System.IOUtils, uVfsTypes, uPlatformProcess;

const
  cGitTimeoutMs = 8000;

type
  /// <summary>Cancel token that asks a function.</summary>
  TFuncCancelToken = class(TInterfacedObject, IJobCancelToken)
  private
    FFunc: TFunc<Boolean>;
  public
    constructor Create(const AFunc: TFunc<Boolean>);
    function IsCancellationRequested: Boolean;
    procedure Cancel;
  end;

constructor TFuncCancelToken.Create(const AFunc: TFunc<Boolean>);
begin
  inherited Create;
  FFunc := AFunc;
end;

function TFuncCancelToken.IsCancellationRequested: Boolean;
begin
  Result := Assigned(FFunc) and FFunc();
end;

procedure TFuncCancelToken.Cancel;
begin
  // Cancellation is decided by the function.
end;

function IsInsideGitWorkTree(const ADir: string): Boolean;
var
  Dir, Parent: string;
begin
  Result := False;
  Dir := ADir;
  while Dir <> '' do
  begin
    if TDirectory.Exists(TPath.Combine(Dir, '.git')) or
       TFile.Exists(TPath.Combine(Dir, '.git')) then
      Exit(True);
    Parent := TPath.GetDirectoryName(Dir);
    if (Parent = Dir) or (Parent = '') then
      Break;
    Dir := Parent;
  end;
end;

function ReadGitStatus(const ADir: string; const ACancelled: TFunc<Boolean>;
  out AStatus: TGitStatus): TGitReadResult;
var
  Text: string;
  Code: Cardinal;
  Token: IJobCancelToken;
begin
  AStatus := Default(TGitStatus);
  if not IsInsideGitWorkTree(ADir) then
    Exit(grNotRepo);
  Token := TFuncCancelToken.Create(ACancelled);
  if PlatformRunCaptured('git',
       ['-C', ADir, '--no-optional-locks', 'status', '--porcelain=v2', '--branch'],
       '', cGitTimeoutMs, Token, Text, Code) <> srOk then
    Exit(grError);
  if (Code <> 0) or not ParseGitStatus(Text, AStatus) then
    Exit(grNotRepo);
  Result := grOk;
end;

end.

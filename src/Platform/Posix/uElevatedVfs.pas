unit uElevatedVfs;

{ Local file operations with administrator rights (POSIX build). A changing
  operation runs as one sudo command (rm, mkdir, cp, mv, cat) and reading goes
  to the ordinary provider. The password is asked for through OnAuthenticate
  when sudo wants one, handed to "sudo -S -v" once and not kept: the commands
  after it rely on sudo's own credential cache ("sudo -n"), which also decides
  when the rights expire. The Windows build lives in Platform\Windows; each
  project puts exactly one of the two directories on its unit search path. }

interface

uses
  System.SysUtils, System.Classes, uVfsTypes, uTextEncoding;

type
  /// <summary>Asks the user for the administrator password and reports
  /// through ADone whether sudo accepted it. Called on the main thread.</summary>
  TElevatedAuthPrompt = reference to procedure(const ADone: TProc<Boolean>);

  TElevatedFileVfs = class(TInterfacedObject, IVirtualFileSystem)
  private
    FInner: IVirtualFileSystem;
    FActive: Boolean;
    FOnActiveChanged: TProc<Boolean>;
    FOnAuthenticate: TElevatedAuthPrompt;
    procedure SetActive(AActive: Boolean);
    procedure Submit(const AArgs: TArray<string>; const AURI: string;
      const AExistsCheck: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      const AStageFile: string = '');
  public
    constructor Create(const AInner: IVirtualFileSystem);
    /// <summary>True after a command ran with the rights and until sudo
    /// stops accepting them.</summary>
    function IsActive: Boolean;
    procedure Shutdown;
    property OnActiveChanged: TProc<Boolean> read FOnActiveChanged
      write FOnActiveChanged;
    property OnAuthenticate: TElevatedAuthPrompt read FOnAuthenticate
      write FOnAuthenticate;

    procedure ListDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsListCallback);
    procedure DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
      ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
      AOnDone: TVfsBoolCallback);
    procedure CreateDirectoryAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsBoolCallback);
    procedure CopyAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure MoveAsync(const AFromURI, AToURI: string; ACancel: IJobCancelToken;
      AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
      AOverwrite: Boolean = False; APreserveTimestamps: Boolean = False);
    procedure ReadTextAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
    procedure ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
      ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
    procedure WriteTextAsync(const AURI, AText: string; AEncoding: TTextFileEncoding;
      ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
    procedure ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsExistsCallback);
    procedure GetFreeSpaceAsync(const ARootURI: string; ACancel: IJobCancelToken;
      AOnDone: TVfsFreeSpaceCallback);
  end;

/// <summary>Runs sudo with AArgs without asking anything (sudo -n); False when
/// sudo is missing. AOutput holds what the command printed.</summary>
function ElevatedRun(const AArgs: TArray<string>; ACancel: IJobCancelToken;
  out AOutput: string; out ACode: Cardinal): Boolean;
/// <summary>True when sudo accepts commands without a password right now.</summary>
function ElevatedSessionOpen: Boolean;
/// <summary>Validates APassword with "sudo -S -v"; AError says why not.</summary>
function ElevatedAuthenticate(const APassword: string; out AError: string): Boolean;

implementation

uses
  System.IOUtils, uPlatformProcess, uVfsUtils;

const
  cAuthWaitMs = 30000;

function ElevatedRun(const AArgs: TArray<string>; ACancel: IJobCancelToken;
  out AOutput: string; out ACode: Cardinal): Boolean;
begin
  Result := PlatformRunCaptured('sudo', ['-n'] + AArgs, '', 0, ACancel, AOutput, ACode) = srOk;
end;

function ElevatedSessionOpen: Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  Result := ElevatedRun(['-v'], nil, Output, Code) and (Code = 0);
end;

function ElevatedAuthenticate(const APassword: string; out AError: string): Boolean;
var
  Output: string;
  Code: Cardinal;
begin
  AError := '';
  Result := (PlatformRunCaptured('sudo', ['-S', '-p', '', '-v'], APassword + #10,
    cAuthWaitMs, nil, Output, Code) = srOk) and (Code = 0);
  if not Result then
  begin
    AError := Trim(Output);
    if AError = '' then
      AError := 'sudo failed';
  end;
end;

function SudoErrorOf(const AOutput, AURI: string; ACode: Cardinal): TVfsError;
var
  Text: string;
begin
  Text := Trim(AOutput);
  if Text.Contains('password is required') or Text.Contains('a terminal is required') then
    Result := TVfsError.Make(vecAccessDenied, 'Administrator rights expired', AURI)
  else if Text.Contains('No such file') then
    Result := TVfsError.Make(vecNotFound, Text, AURI)
  else if Text.Contains('File exists') then
    Result := TVfsError.Make(vecAlreadyExists, Text, AURI)
  else if Text.Contains('Permission denied') or Text.Contains('not in the sudoers') then
    Result := TVfsError.Make(vecAccessDenied, Text, AURI)
  else if Text = '' then
    Result := TVfsError.Make(vecIOError, 'Command failed with code ' + IntToStr(ACode), AURI)
  else
    Result := TVfsError.Make(vecIOError, Text, AURI);
end;

constructor TElevatedFileVfs.Create(const AInner: IVirtualFileSystem);
begin
  inherited Create;
  FInner := AInner;
end;

function TElevatedFileVfs.IsActive: Boolean;
begin
  Result := FActive;
end;

procedure TElevatedFileVfs.Shutdown;
begin
  FOnActiveChanged := nil;
  FOnAuthenticate := nil;
end;

procedure TElevatedFileVfs.SetActive(AActive: Boolean);
begin
  if FActive = AActive then
    Exit;
  FActive := AActive;
  if Assigned(FOnActiveChanged) then
    FOnActiveChanged(AActive);
end;

// Runs sudo with AArgs on a worker thread. AExistsCheck, when set, is a path
// that must not exist yet (no overwrite); AStageFile is deleted at the end.
procedure TElevatedFileVfs.Submit(const AArgs: TArray<string>; const AURI: string;
  const AExistsCheck: string; ACancel: IJobCancelToken;
  AOnProgress: TVfsProgressCallback; AOnDone: TVfsBoolCallback;
  const AStageFile: string);
var
  Self_: TElevatedFileVfs;
  Run: TProc;
begin
  Self_ := Self;
  Run :=
    procedure
    begin
      TThread.CreateAnonymousThread(
        procedure
        var
          Output: string;
          Code: Cardinal;
          Err: TVfsError;
          Ok: Boolean;
          ExistsOut: string;
          ExistsCode: Cardinal;
        begin
          Err := TVfsError.Make(vecOk, '', AURI);
          Ok := False;
          if (AExistsCheck <> '') and ElevatedRun(['test', '-e', AExistsCheck], ACancel,
               ExistsOut, ExistsCode) and (ExistsCode = 0) then
            Err := TVfsError.Make(vecAlreadyExists, 'Already exists', AExistsCheck)
          else if (ACancel <> nil) and ACancel.IsCancellationRequested then
            Err := TVfsError.Make(vecCancelled, 'Cancelled', AURI)
          else if not ElevatedRun(AArgs, ACancel, Output, Code) then
            Err := TVfsError.Make(vecNotSupported, 'sudo is not available', AURI)
          else if Code <> 0 then
            Err := SudoErrorOf(Output, AURI, Code)
          else
            Ok := True;
          if AStageFile <> '' then
            try
              TFile.Delete(AStageFile);
            except
              // A leftover staging file in the temp folder is harmless.
            end;
          TThread.Queue(nil,
            procedure
            begin
              if Ok then
              begin
                Self_.SetActive(True);
                if Assigned(AOnProgress) then
                  AOnProgress(1, 1, '', 0, 0, '', '');
              end
              else if Err.Code = vecAccessDenied then
                Self_.SetActive(False);
              if Assigned(AOnDone) then
                AOnDone(Ok, Err);
            end);
        end).Start;
    end;

  // A session that is not open yet asks for the password first.
  TThread.CreateAnonymousThread(
    procedure
    var
      Open: Boolean;
    begin
      Open := ElevatedSessionOpen;
      TThread.Queue(nil,
        procedure
        begin
          if Open then
            Run()
          else if not Assigned(Self_.FOnAuthenticate) then
          begin
            if Assigned(AOnDone) then
              AOnDone(False, TVfsError.Make(vecAccessDenied,
                'Administrator rights are not available', AURI));
          end
          else
            Self_.FOnAuthenticate(
              procedure(AAccepted: Boolean)
              begin
                if AAccepted then
                  Run()
                else if Assigned(AOnDone) then
                  AOnDone(False, TVfsError.Make(vecAccessDenied,
                    'Administrator password was not accepted', AURI));
              end);
        end);
    end).Start;
end;

procedure TElevatedFileVfs.DeleteAsync(const AURI: string; AMode: TVfsDeleteMode;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback);
var
  Path: string;
begin
  Path := FileUriToPath(AURI);
  // The command runs with administrator rights: the root of the file system
  // is refused before sudo is even asked for.
  if IsVolumeRootPath(Path) then
  begin
    if Assigned(AOnDone) then
      AOnDone(False, TVfsError.Make(vecNotSupported, 'A volume root cannot be deleted', AURI));
    Exit;
  end;
  Submit(['rm', '-rf', '--', Path], AURI, '', ACancel, AOnProgress, AOnDone);
end;

procedure TElevatedFileVfs.CreateDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
begin
  Submit(['mkdir', '--', FileUriToPath(AURI)], AURI, '', ACancel, nil, AOnDone);
end;

procedure TElevatedFileVfs.CopyAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
var
  Args: TArray<string>;
  Check: string;
begin
  Args := ['cp', '-r', '-T'];
  if APreserveTimestamps then
    Args := Args + ['-p'];
  if AOverwrite then
    Args := Args + ['-f']
  else
    Check := FileUriToPath(AToURI);
  Args := Args + ['--', FileUriToPath(AFromURI), FileUriToPath(AToURI)];
  Submit(Args, AFromURI, Check, ACancel, AOnProgress, AOnDone);
end;

procedure TElevatedFileVfs.MoveAsync(const AFromURI, AToURI: string;
  ACancel: IJobCancelToken; AOnProgress: TVfsProgressCallback;
  AOnDone: TVfsBoolCallback; AOverwrite, APreserveTimestamps: Boolean);
var
  Check: string;
begin
  if not AOverwrite then
    Check := FileUriToPath(AToURI);
  Submit(['mv', '-f', '-T', '--', FileUriToPath(AFromURI), FileUriToPath(AToURI)],
    AFromURI, Check, ACancel, AOnProgress, AOnDone);
end;

// The text goes to a temporary file the command copies over the target, so an
// existing file keeps its owner and mode.
procedure TElevatedFileVfs.WriteTextAsync(const AURI, AText: string;
  AEncoding: TTextFileEncoding; ACancel: IJobCancelToken; AOnDone: TVfsBoolCallback);
var
  Stage: string;
begin
  Stage := TPath.Combine(TPath.GetTempPath, 'mtn2-elev-' + TPath.GetGUIDFileName(False));
  try
    TFile.WriteAllBytes(Stage, EncodeTextBytes(AText, AEncoding));
  except
    on E: Exception do
    begin
      if Assigned(AOnDone) then
        AOnDone(False, TVfsError.Make(vecIOError, E.Message, AURI));
      Exit;
    end;
  end;
  Submit(['sh', '-c', 'cat "$1" > "$2"', 'sh', Stage, FileUriToPath(AURI)], AURI, '',
    ACancel, nil, AOnDone, Stage);
end;

procedure TElevatedFileVfs.ListDirectoryAsync(const AURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsListCallback);
begin
  FInner.ListDirectoryAsync(AURI, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.ReadTextAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsTextCallback);
begin
  FInner.ReadTextAsync(AURI, AMaxBytes, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.ReadBytesAsync(const AURI: string; AMaxBytes: Int64;
  ACancel: IJobCancelToken; AOnDone: TVfsBytesCallback);
begin
  FInner.ReadBytesAsync(AURI, AMaxBytes, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.ExistsAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnDone: TVfsExistsCallback);
begin
  FInner.ExistsAsync(AURI, ACancel, AOnDone);
end;

procedure TElevatedFileVfs.GetFreeSpaceAsync(const ARootURI: string;
  ACancel: IJobCancelToken; AOnDone: TVfsFreeSpaceCallback);
begin
  FInner.GetFreeSpaceAsync(ARootURI, ACancel, AOnDone);
end;

end.

unit uFileRecycleBin;

{ Deleting a local path into the user's trash (POSIX build), following the
  freedesktop.org Trash specification for the home trash: the item is moved to
  Trash/files and a matching Trash/info/<name>.trashinfo records where it came
  from. A move that cannot be done (another file system, no permission) is
  reported as an error so the caller can offer a permanent delete. The Windows
  build lives in Platform\Windows. }

interface

uses
  uVfsTypes;

var
  /// <summary>Owner window of the Shell's own prompts; unused here.</summary>
  GRecycleOwnerWindow: NativeUInt = 0;

/// <summary>The user's trash directory, which holds the files and info
/// subdirectories.</summary>
function TrashDirectory: string;

procedure DeleteToRecycleBin(const APath: string; var AError: TVfsError;
  AOnProgress: TVfsProgressCallback = nil; const ACancel: IJobCancelToken = nil);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Posix.Base, Posix.Errno;

function c_rename(AOld, ANew: MarshaledAString): Integer; cdecl;
  external libc name 'rename';

function TrashDirectory: string;
var
  Base: string;
begin
  Base := GetEnvironmentVariable('XDG_DATA_HOME');
  if Base = '' then
    Base := TPath.Combine(GetEnvironmentVariable('HOME'), '.local/share');
  Result := TPath.Combine(Base, 'Trash');
end;

// Percent-encodes everything but unreserved characters and '/', as the
// trashinfo Path key requires.
function EncodeTrashPath(const APath: string): string;
const
  Hex = '0123456789ABCDEF';
var
  Bytes: TBytes;
  B: Byte;
begin
  Result := '';
  Bytes := TEncoding.UTF8.GetBytes(APath);
  for B in Bytes do
    if (B < 128) and (Char(B) in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~', '/']) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + Hex[(B shr 4) + 1] + Hex[(B and 15) + 1];
end;

function UniqueTrashName(const AFilesDir, AInfoDir, AName: string): string;
var
  N: Integer;
begin
  Result := AName;
  N := 1;
  while TFile.Exists(TPath.Combine(AFilesDir, Result)) or
        TDirectory.Exists(TPath.Combine(AFilesDir, Result)) or
        TFile.Exists(TPath.Combine(AInfoDir, Result + '.trashinfo')) do
  begin
    Inc(N);
    Result := AName + '.' + IntToStr(N);
  end;
end;

procedure DeleteToRecycleBin(const APath: string; var AError: TVfsError;
  AOnProgress: TVfsProgressCallback; const ACancel: IJobCancelToken);
var
  Full, Root, FilesDir, InfoDir, Name, InfoPath, Dest: string;
  A, B: UTF8String;
begin
  Full := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath));
  Root := TrashDirectory;
  FilesDir := TPath.Combine(Root, 'files');
  InfoDir := TPath.Combine(Root, 'info');
  try
    ForceDirectories(FilesDir);
    ForceDirectories(InfoDir);
    Name := UniqueTrashName(FilesDir, InfoDir, ExtractFileName(Full));
    InfoPath := TPath.Combine(InfoDir, Name + '.trashinfo');
    Dest := TPath.Combine(FilesDir, Name);
    TFile.WriteAllText(InfoPath,
      '[Trash Info]'#10 +
      'Path=' + EncodeTrashPath(Full) + #10 +
      'DeletionDate=' + FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now) + #10,
      TUTF8Encoding.Create(False));
  except
    on E: Exception do
    begin
      AError := TVfsError.Make(vecIOError, E.Message, PathToFileUri(APath));
      Exit;
    end;
  end;
  A := UTF8String(Full);
  B := UTF8String(Dest);
  if c_rename(MarshaledAString(A), MarshaledAString(B)) <> 0 then
  begin
    TFile.Delete(InfoPath);
    AError := TVfsError.Make(vecIOError, SysErrorMessage(GetLastError),
      PathToFileUri(APath));
  end;
end;

end.

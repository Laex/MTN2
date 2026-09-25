unit uFolderSize;

{ Async folder-size calculation (FAR F3-on-directory). Walks local trees off the
  UI thread; single-layer ZIP uses the CD prefix tree. }

interface

uses
  System.SysUtils, System.Classes,
  uVfsTypes;

type
  TFolderSizeProgressCallback = reference to procedure(ABytes: Int64;
    AFiles, AFolders: Integer; const ACurrentDir: string);
  TFolderSizeDoneCallback = reference to procedure(ABytes: Int64;
    AFiles, AFolders: Integer; const AError: TVfsError);

procedure CalculateFolderSizeAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnProgress: TFolderSizeProgressCallback; AOnDone: TFolderSizeDoneCallback);

implementation

uses
  System.IOUtils, System.Generics.Collections,
  uZipVfs;

procedure CalculateLocalFolderSize(const APath: string; ACancel: IJobCancelToken;
  AOnProgress: TFolderSizeProgressCallback; out ABytes: Int64;
  out AFiles, AFolders: Integer; out AError: TVfsError);
var
  Stack: TStack<string>;
  Dir, Full, Name: string;
  SR: TSearchRec;
  Code: Integer;
  LastTick: Cardinal;
  Root: string;
  Bytes: Int64;
  Files, Folders: Integer;

  procedure EmitProgress(const ADir: string);
  var
    CapBytes: Int64;
    CapFiles, CapFolders: Integer;
    CapDir: string;
  begin
    if not Assigned(AOnProgress) then
      Exit;
    if (LastTick <> 0) and (TThread.GetTickCount - LastTick < 80) then
      Exit;
    LastTick := TThread.GetTickCount;
    CapBytes := Bytes;
    CapFiles := Files;
    CapFolders := Folders;
    CapDir := ADir;
    TThread.Queue(nil,
      procedure
      begin
        if Assigned(AOnProgress) then
          AOnProgress(CapBytes, CapFiles, CapFolders, CapDir);
      end);
  end;

begin
  Bytes := 0;
  Files := 0;
  Folders := 0;
  AError := TVfsError.Ok;
  LastTick := 0;
  Root := ExcludeTrailingPathDelimiter(APath);
  if Root = '' then
  begin
    AError := TVfsError.Make(vecInvalidURI, 'Invalid path', PathToFileUri(APath));
    ABytes := 0;
    AFiles := 0;
    AFolders := 0;
    Exit;
  end;
  if not TDirectory.Exists(Root) then
  begin
    AError := TVfsError.Make(vecNotFound, 'Path not found', PathToFileUri(Root));
    ABytes := 0;
    AFiles := 0;
    AFolders := 0;
    Exit;
  end;

  Stack := TStack<string>.Create;
  try
    Stack.Push(Root);
    while (Stack.Count > 0) and not JobCancelRequested(ACancel) do
    begin
      Dir := Stack.Pop;
      EmitProgress(Dir);
      Code := FindFirst(TPath.Combine(Dir, '*'), faAnyFile, SR);
      try
        while Code = 0 do
        begin
          if JobCancelRequested(ACancel) then
            Break;
          Name := SR.Name;
          if (Name <> '.') and (Name <> '..') then
          begin
            Full := TPath.Combine(Dir, Name);
            if (SR.Attr and faDirectory) <> 0 then
            begin
              Inc(Folders);
              Stack.Push(Full);
            end
            else
            begin
              Inc(Files);
              Inc(Bytes, SR.Size);
            end;
          end;
          Code := FindNext(SR);
        end;
      finally
        System.SysUtils.FindClose(SR);
      end;
    end;
  finally
    Stack.Free;
  end;

  ABytes := Bytes;
  AFiles := Files;
  AFolders := Folders;
  if JobCancelRequested(ACancel) then
    AError := TVfsError.Make(vecCancelled, 'Cancelled', PathToFileUri(Root));
end;

procedure CalculateFolderSizeAsync(const AURI: string; ACancel: IJobCancelToken;
  AOnProgress: TFolderSizeProgressCallback; AOnDone: TFolderSizeDoneCallback);
var
  URI: string;
  Cancel: IJobCancelToken;
  OnProgress: TFolderSizeProgressCallback;
  OnDone: TFolderSizeDoneCallback;
begin
  URI := AURI;
  Cancel := ACancel;
  OnProgress := AOnProgress;
  OnDone := AOnDone;

  TThread.CreateAnonymousThread(
    procedure
    var
      Bytes: Int64;
      Files, Folders: Integer;
      Err: TVfsError;
      Path: string;
      CapBytes: Int64;
      CapFiles, CapFolders: Integer;
      CapErr: TVfsError;
      CapDone: TFolderSizeDoneCallback;
    begin
      Bytes := 0;
      Files := 0;
      Folders := 0;
      Err := TVfsError.Ok;
      try
        if JobCancelRequested(Cancel) then
          Err := TVfsError.Make(vecCancelled, 'Cancelled', URI)
        else if HasArchiveChain(URI) then
          CalculateZipFolderSize(URI, Cancel, Bytes, Files, Folders, Err)
        else
        begin
          Path := FileUriToPath(URI);
          CalculateLocalFolderSize(Path, Cancel, OnProgress, Bytes, Files,
            Folders, Err);
        end;
      except
        on E: Exception do
          Err := TVfsError.Make(vecIOError, E.Message, URI);
      end;

      CapDone := OnDone;
      if Assigned(CapDone) then
      begin
        CapBytes := Bytes;
        CapFiles := Files;
        CapFolders := Folders;
        CapErr := Err;
        TThread.Queue(nil,
          procedure
          begin
            CapDone(CapBytes, CapFiles, CapFolders, CapErr);
          end);
      end;
    end).Start;
end;

end.

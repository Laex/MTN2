unit uPictureStage;

{ Gives the picture preview of the POSIX hosts a local file to decode. A local
  file:// URI is used where it is; a picture inside an archive or on a remote
  server is read through the virtual file system and written to a temporary
  file, which the caller deletes once the picture is decoded. Must be called
  on the main thread: the read answers there. }

interface

type
  /// <summary>APath is the file to decode ('' when the picture cannot be read);
  /// ATemp is True when the caller must delete it after use.</summary>
  TPictureStageDone = reference to procedure(const APath: string; ATemp: Boolean);

const
  cPictureStageMaxBytes = 32 * 1024 * 1024;

procedure StagePictureFile(const AURI: string; ADone: TPictureStageDone);

implementation

uses
  System.SysUtils, System.IOUtils, uVfsTypes, uVfsRegistry;

procedure StagePictureFile(const AURI: string; ADone: TPictureStageDone);
var
  Path: string;
begin
  if HasArchiveChain(AURI) then
    Path := ''
  else
    Path := FileUriToPath(AURI);
  if Path <> '' then
  begin
    if TFile.Exists(Path) then
      ADone(Path, False)
    else
      ADone('', False);
    Exit;
  end;
  CreateDefaultVfs.ReadBytesAsync(AURI, cPictureStageMaxBytes, TJobCancelToken.Create,
    procedure(const ABytes: TBytes; const AError: TVfsError)
    var
      Temp: string;
    begin
      if (AError.Code <> vecOk) or (Length(ABytes) = 0) then
      begin
        ADone('', False);
        Exit;
      end;
      Temp := TPath.Combine(TPath.GetTempPath,
        'mtn2-pic-' + TPath.GetGUIDFileName(False) + ExtractFileExt(AURI));
      try
        TFile.WriteAllBytes(Temp, ABytes);
      except
        ADone('', False);
        Exit;
      end;
      ADone(Temp, True);
    end);
end;

end.

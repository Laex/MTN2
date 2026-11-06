unit uMetaReader;

{ Reads the first bytes of a file and describes it in one line. }

interface

/// <summary>The one-line description of a local file; '' for a file with no metadata,
/// an unknown kind or a damaged header.</summary>
function DescribeFile(const APath: string): string;

type
  /// <summary>What a file panel column shows for a file; a field is '' when the
  /// file has nothing for it.</summary>
  TMetaCells = record
    /// <summary>"1920x1080" of an image.</summary>
    Dimensions: string;
    Camera: string;
    Artist: string;
    Title: string;
    Album: string;
    Year: string;
    /// <summary>"1.2.3.4" of an executable or library (Windows).</summary>
    Version: string;
    /// <summary>The version as a number that sorts like the version does.</summary>
    VersionKey: Int64;
    Company: string;
    Description: string;
  end;

/// <summary>The panel column values of a local file; all '' for a file with no
/// metadata, an unknown kind or a damaged header.</summary>
function ReadFileCells(const APath: string): TMetaCells;

implementation

uses
  System.SysUtils, System.Classes, uMetaFormat
  {$IFDEF MSWINDOWS}, uMetaPeVersion{$ENDIF};

// Up to ACount bytes from AOffset; fewer at the end of the file.
function ReadBytesAt(const APath: string; AOffset: Int64; ACount: Integer): TBytes;
var
  Stream: TFileStream;
  Got: Integer;
begin
  Result := nil;
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if (AOffset < 0) or (AOffset > Stream.Size) then
      Exit;
    Stream.Position := AOffset;
    SetLength(Result, ACount);
    Got := Stream.Read(Result[0], ACount);
    SetLength(Result, Got);
  finally
    Stream.Free;
  end;
end;

function FileSizeOf(const APath: string): Int64;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

function DescribeImage(const APath: string): string;
var
  Info: TImageInfo;
begin
  Result := '';
  if ParseImageInfo(ReadBytesAt(APath, 0, cImageHeadBytes), Info) then
    Result := ImageSummary(Info);
end;

// The ID3v2 tag, else the ID3v1 tag at the end of the file.
function ReadAudioTags(const APath: string; out ATags: TAudioTags): Boolean;
var
  Head, Tail: TBytes;
  Size: Integer;
  FileSize: Int64;
begin
  Result := False;
  Head := ReadBytesAt(APath, 0, 10);
  Size := Id3v2TagSize(Head);
  if Size > 0 then
  begin
    if Size > cMaxId3Bytes then
      Size := cMaxId3Bytes;
    if ParseId3v2(ReadBytesAt(APath, 0, Size), ATags) then
      Exit(True);
  end;
  FileSize := FileSizeOf(APath);
  if FileSize >= cId3v1Bytes then
  begin
    Tail := ReadBytesAt(APath, FileSize - cId3v1Bytes, cId3v1Bytes);
    Result := ParseId3v1(Tail, ATags);
  end;
end;

function DescribeAudio(const APath: string): string;
var
  Tags: TAudioTags;
begin
  Result := '';
  if ReadAudioTags(APath, Tags) then
    Result := AudioSummary(Tags);
end;

function ReadFileCells(const APath: string): TMetaCells;
var
  Kind: string;
  Info: TImageInfo;
  Tags: TAudioTags;
  {$IFDEF MSWINDOWS}
  Pe: TPeVersion;
  {$ENDIF}
begin
  Result := Default(TMetaCells);
  Kind := MetaKindOf(APath);
  try
    if Kind = 'image' then
    begin
      if ParseImageInfo(ReadBytesAt(APath, 0, cImageHeadBytes), Info) and (Info.Format <> '') then
      begin
        Result.Dimensions := Format('%dx%d', [Info.Width, Info.Height]);
        Result.Camera := Info.Camera;
      end;
    end
    else if Kind = 'audio' then
    begin
      if ReadAudioTags(APath, Tags) then
      begin
        Result.Artist := Tags.Artist;
        Result.Title := Tags.Title;
        Result.Album := Tags.Album;
        Result.Year := Tags.Year;
      end;
    end
    {$IFDEF MSWINDOWS}
    else if Kind = 'exe' then
    begin
      if ReadPeVersion(APath, Pe) then
      begin
        Result.Version := Pe.Version;
        Result.VersionKey := Pe.VersionKey;
        Result.Company := Pe.Company;
        Result.Description := Pe.Description;
      end;
    end
    {$ENDIF};
  except
    // A file that cannot be opened or read has no cells.
    Result := Default(TMetaCells);
  end;
end;

function DescribeFile(const APath: string): string;
var
  Kind: string;
begin
  Result := '';
  Kind := MetaKindOf(APath);
  if Kind = '' then
    Exit;
  try
    if Kind = 'image' then
      Result := DescribeImage(APath)
    else if Kind = 'audio' then
      Result := DescribeAudio(APath)
    {$IFDEF MSWINDOWS}
    else if Kind = 'exe' then
      Result := ReadPeVersionSummary(APath)
    {$ENDIF};
  except
    // A file that cannot be opened or read has no description.
    Result := '';
  end;
end;

end.

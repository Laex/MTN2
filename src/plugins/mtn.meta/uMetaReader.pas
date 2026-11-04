unit uMetaReader;

{ Reads the first bytes of a file and describes it in one line. }

interface

/// <summary>The one-line description of a local file; '' for a file with no metadata,
/// an unknown kind or a damaged header.</summary>
function DescribeFile(const APath: string): string;

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

function DescribeAudio(const APath: string): string;
var
  Head, Tail: TBytes;
  Tags: TAudioTags;
  Size: Integer;
  FileSize: Int64;
begin
  Result := '';
  Head := ReadBytesAt(APath, 0, 10);
  Size := Id3v2TagSize(Head);
  if Size > 0 then
  begin
    if Size > cMaxId3Bytes then
      Size := cMaxId3Bytes;
    if ParseId3v2(ReadBytesAt(APath, 0, Size), Tags) then
      Exit(AudioSummary(Tags));
  end;
  FileSize := FileSizeOf(APath);
  if FileSize >= cId3v1Bytes then
  begin
    Tail := ReadBytesAt(APath, FileSize - cId3v1Bytes, cId3v1Bytes);
    if ParseId3v1(Tail, Tags) then
      Result := AudioSummary(Tags);
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

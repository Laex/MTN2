unit uFileClip;

{ Conversions between panel URIs and local paths, and the text form of a
  copied or cut list of panel items. Shared by every clipboard and drag
  implementation. }

interface

/// <summary>file:// URIs -> absolute local paths (skips archives / non-file).</summary>
function FileUrisToLocalPaths(const AUris: TArray<string>): TArray<string>;

/// <summary>Local paths -> file:// URIs.</summary>
function LocalPathsToFileUris(const APaths: TArray<string>): TArray<string>;

/// <summary>Serialize panel URIs for the MTN2 clipboard format.</summary>
function EncodeMtnFileClip(const AUris: TArray<string>; ACut: Boolean): string;
/// <summary>Parse EncodeMtnFileClip text. False if the payload is empty/unknown.</summary>
function DecodeMtnFileClip(const AText: string; out AUris: TArray<string>;
  out ACut: Boolean): Boolean;

implementation

uses
  System.SysUtils, uVfsTypes;

function FileUrisToLocalPaths(const AUris: TArray<string>): TArray<string>;
var
  U, Path: string;
  N: Integer;
begin
  SetLength(Result, 0);
  for U in AUris do
  begin
    if U = '' then
      Continue;
    if HasArchiveChain(U) or IsFindUri(U) or IsSystemFoldersUri(U) then
      Continue;
    Path := FileUriToPath(U);
    if Path = '' then
      Continue;
    if not (LocalPathIsFile(Path) or LocalPathIsDirectory(Path)) then
      Continue;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := Path;
  end;
end;

function LocalPathsToFileUris(const APaths: TArray<string>): TArray<string>;
var
  P: string;
  N: Integer;
begin
  SetLength(Result, 0);
  for P in APaths do
  begin
    if Trim(P) = '' then
      Continue;
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N] := PathToFileUri(P);
  end;
end;

function EncodeMtnFileClip(const AUris: TArray<string>; ACut: Boolean): string;
var
  I: Integer;
  Text: TStringBuilder;
begin
  // One buffer for the payload. Appending each URI stalls copying a large
  // selection.
  Text := TStringBuilder.Create;
  try
    if ACut then
      Text.Append('CUT')
    else
      Text.Append('COPY');
    for I := 0 to High(AUris) do
      if Trim(AUris[I]) <> '' then
      begin
        Text.Append(#10);
        Text.Append(AUris[I]);
      end;
    Result := Text.ToString;
  finally
    Text.Free;
  end;
end;

function DecodeMtnFileClip(const AText: string; out AUris: TArray<string>;
  out ACut: Boolean): Boolean;
var
  Lines: TArray<string>;
  Head: string;
  I, N: Integer;
begin
  Result := False;
  ACut := False;
  SetLength(AUris, 0);
  Lines := AText.Split([#10, #13], TStringSplitOptions.ExcludeEmpty);
  if Length(Lines) = 0 then
    Exit;
  Head := UpperCase(Trim(Lines[0]));
  if Head = 'CUT' then
    ACut := True
  else if Head = 'COPY' then
    ACut := False
  else
    Exit;
  SetLength(AUris, Length(Lines) - 1);
  N := 0;
  for I := 1 to High(Lines) do
  begin
    AUris[N] := Trim(Lines[I]);
    if AUris[N] <> '' then
      Inc(N);
  end;
  SetLength(AUris, N);
  Result := N > 0;
end;

end.
